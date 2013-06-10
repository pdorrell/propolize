require 'erb'

module Propolize
  
  # Propolize defines a very specific and constrained document structure which supports "propositional writing"
  # It is similiar to Markdown, but with a limited set of Markdown features, and with some extensions
  # particular to this document structure.
  #
  # Propolize source code consists of the following types of 'chunk', where each chunk is one or more lines:
  #
  # 1. A special property definition or tag (starting with '##' at the beginning of the line)
  # 2. A list (which will map to an HTML list) which starts with '* ' at the beginning of the line for each list item.
  #    (The end of the list is marked by a blank line.)
  # 3. A 'proposition' (a special type of heading), which starts with '# ' at the beginning of the line
  # 4. A secondary heading - a line with a following line containing only '---------' characters
  # 5. A paragraph - starting with a line which is not any of the above
  # 
  # Special property definitions and tags are only one line. All other chunks are terminated by a blank
  # line or the end of the file.
  #
  # A propositional document also has a higher level structure in that it consists of an introduction followed
  # by a sequence of propositions-with-explanations, followed by an optional appendix.
  #
  # The introduction consists only of lists or paragraphs (i.e. no secondary headings)
  #
  # Each proposition can be followed by zero or more lists of paragraphs (there are no secondary headings)
  #
  # The appendix consists of a sequence of secondary headings, lists or paragraphs.
  # The appendix is started by a special '##appendix' tag
  #
  # Special property tags can occur anywhere. They are of the form
  # ##date 23 May, 2014
  #
  # (which defines the 'date' property to be '23 May, 2014')
  #
  # Required properties are 'date', 'author' and 'title'.
  # (Note: properties can be passed in via the 'properties' argument of the 'propolize' method, 
  #  in which case they do not need to appear in the source code.)
  #
  # Detailed markup occurs within 'text' sections, these occur in the following contexts:
  # * Propositions
  # * Paragraphs
  # * List items
  # * Secondary headings
  # * Text inside link definitions (see below)
  #
  # The detailed markup includes the following:
  #
  # * '*' to delineate italic text
  # * '**' to delineate bold text
  # * '[]' for anchor targets for the form '[name:]' for normal anchors, and '[name::]' for numbered footnote anchors
  # * '[]()' for links as in '[http://example.com/](An example website)'. Three types of URL definition exist -
  #   * [name:] for normal anchors
  #   * [name::] for numbered footnote anchors
  #   * [url] for all other URL's
  #
  # There is also a post-processing step where '--' is converted into '&ndash;'
  #
  # Two other special items parsed are:
  # * '\' followed by a character will output the HTML-escaped version of that character
  # * HTML entities (e.g. '&ndash;') are output as is
  #
  # There are two special qualifiers that may occur at the beginning of a list or a paragraph:
  #  
  # * '#:<tag>' where <tag> is a special tag (currently the only option is "bq" for "blockquote")
  # * '?? ', which qualifies the item as being part of the 'critique' where a propositional document
  #   is being written as a critique of some other propositional document
  #
  #
  # All other text is output as HTML-escaped text.

  module Helpers
    def html_escape(s)
      s.to_s.gsub(/&/, "&amp;").gsub(/>/, "&gt;").gsub(/</, "&lt;")
    end
    
    alias h html_escape
  end

  # A very simple string buffer that maintains data as an array of strings
  # and joins them all together when the final result is required.
  class StringBuffer
    def initialize
      @strings = []
    end
    
    def write(string)
      @strings.push(string)
    end
    
    def to_string
      return @strings.join("")
    end
  end
  
  # A proposition with an explanation. The proposition is effectively the headline, 
  # and the explanation is a sequence of "explanation items" (i.e. paragraphs).
  class PropositionWithExplanation
    # Create with initial proposition (and empty list of explanation items)
    def initialize(proposition)
      @proposition = proposition
      @explanationItems = []
    end
    
    # Add one explanation item to the list of explanation items
    def addExplanationItem(item)
      @explanationItems.push(item)
    end
    
    # Dump to stdout (for debugging/tracing)
    def dump(indent)
      puts ("#{indent}#{@proposition}")
      for item in @explanationItems do
        puts ("#{indent}  #{item}")
      end
    end
    
    # Output as HTML (Each proposition is one item in a list of propositions, so it is output as a <li> item.)
    def toHtml
      return "<li>\n#{@proposition.toHtml}\n#{@explanationItems.map(&:toHtml).join("\n")}\n</li>"
    end
    
  end
  
  # A section of source text being processed as part of a document
  class TextBeingProcessed
    
    include Helpers
    
    # Parsers in order of priority - each one is a pair consisting of:
    # 1. regex to greedily match as much as possible of the text being parsed, and 
    # 2. the name of the processing method to call, passing in the match values
    
    # Plain text, any text not containing '\', '*', '[' or '&'
    @@plainTextParser = [/\A[^\\\*\[&]+/m, :processPlainText]
    
    # Backslash item, '\' followed by the quoted character
    @@backslashParser = [/\A\\(.)/m, :processBackslash]
    
    # An HTML entity, starts with '&', then an alphanumerical identifier, or, '#' + a number, followed by ';'
    @@entityParser = [/\A&(([A-Za-z0-9]+)|(#[0-9]+));/m, :processEntity]
    
    # A pair of asterisks
    @@doubleAsterixParser = [/\A\*\*/m, :processDoubleAsterix]
    
    # A single asterisk
    @@singleAsterixParser = [/\A\*/m, :processSingleAsterix]
    
    # text enclosed by '[' and ']', with an optional following section enclosed by '(' and ')'
    @@linkOrAnchorParser = [/\A\[([^\]]*)\](\(([^\)]+)\)|)/m, :processLinkOrAnchor]

    # Parsers to be applied inside link text (everything _except_ the link/anchor parser)
    @@linkTextParsers = [@@plainTextParser, @@backslashParser, @@entityParser, 
                         @@doubleAsterixParser, @@singleAsterixParser]
    
    # Parsers to be applied outside link text
    @@fullTextParsers = @@linkTextParsers + [@@linkOrAnchorParser]
    
    # Initialise - 
    # document - source document
    # text - the actual text string
    # writer - to which the output is written
    # weAreInsideALink - are we inside a link? (if so, don't attempt to parse any inner links)
    def initialize(document, text, writer, weAreInsideALink)
      @document = document
      @text = text
      @writer = writer
      @pos = 0
      @italic = false
      @bold = false
      # if we are inside a link (i.e. to be output as <a> tag), _don't_ attempt to parse any links within that link
      @parsers = if weAreInsideALink then @@linkTextParsers else @@fullTextParsers end
    end
    
    # Process plain text by writing out HTML-escaped text
    def processPlainText(match)
      @writer.write(html_escape(match[0]))
    end
    
    # Process a backslash-quoted character by writing it out as HTML-escaped text
    def processBackslash(match)
      @writer.write(html_escape(match[1]))
    end

    # Process an HTML entity by writing it out as is
    def processEntity(match)
      @writer.write(match[0])
    end
    
    # Process a double asterix by either starting or finishing an HTML bold section.
    def processDoubleAsterix(match)
      if @bold then
        @writer.write("</b>")
        @bold = false
      else
        @writer.write("<b>")
        @bold = true
      end
    end
    
    # Process a single asterix by either starting or finishing an HTML italic section.
    def processSingleAsterix(match)
      if @italic then
        @writer.write("</i>")
        @italic = false
      else
        @writer.write("<i>")
        @italic = true
      end
    end
    
    # Process a link definition which consists of a URL definition followed by a text definition
    # Special cases of a URL definition are 
    # 1. Footnote, represented by a unique footnote identifier followed by '::'
    # 2. Anchor link, represented by the anchor name followed by ':'
    # The text definition is recursively parsed, except that link and anchor definitions
    # cannot occur inside the text definition (or rather, they are just ignored).
    def processLink (text, url)
      anchorMatch = /^([^\/:]*):$/.match(url)
      footnoteMatch = /^([^\/:]*)::$/.match(url)
      linkTextHtml = @document.processText(text, :weAreInsideALink => true)
      if footnoteMatch then 
        footnoteName = footnoteMatch[1]
        # The footnote has a name (i.e. unique identifier) in the source code, but the footnotes
        # are assigned sequential numbers in the output text.
        footnoteNumber = @document.getNewFootnoteNumberFor(footnoteName)
        @writer.write("<a href=\"##{footnoteName}\" class=\"footnote\">#{footnoteNumber}</a>")
      elsif anchorMatch then
        @writer.write("<a href=\"##{anchorMatch[1]}\">#{linkTextHtml}</a>")
      else
        @writer.write("<a href=\"#{url}\">#{linkTextHtml}</a>")
      end
    end
    
    # Process an anchor definition which consists of either:
    # 1. An normal anchor definition consisting of the anchor name followed by ':', or, 
    # 2. A footnote, consisting of the footnote identifier followed by '::' (the footnote identifier is also
    # the anchor name) This is output as the actual footnote number (assigned previously when a link to the
    # footnote was given), and the HTML anchor.
    def processAnchor(url)
      anchorMatch = /^([^\/:]*):$/.match(url)
      if anchorMatch
        @writer.write("<a name=\"#{anchorMatch[1]}\"></a>")
      else
        footnoteMatch = /^([^\/:]*)::$/.match(url)
        if footnoteMatch
          footnoteName = footnoteMatch[1]
          footnoteNumberString = @document.footnoteNumberFor(footnoteName)
          @writer.write("<span class=\"footnoteNumber\">#{footnoteNumberString}</span>" + 
                        "<a name=\"#{footnoteName}\"></a>")
        else
          raise DocumentError, "Invalid URL for anchor: #{url.inspect}"
        end
      end
    end
    
    # Process a link consisting of [] and optional () section. If the () section is not given, 
    # then it is an HTML anchor definition (<a name>), otherwise it represents an HTML link (<a href>).
    def processLinkOrAnchor(match)
      if match[3] then
        processLink(match[1], match[3])
      else
        processAnchor(match[1])
      end
    end
    
    # If the '*' or '**' values are not balanced, complain.
    def checkValidAtEnd
      if @bold then
        raise DocumentError, "unclosed bold span"
      end
      if @italic then
        raise DocumentError, "unclosed italic span"
      end
    end
    
    # Having parsed some of the text, how much is left to be parsed?
    def textNotYetParsed
      return @text[@pos..-1]
    end
    
    # Parse the source text by repeatedly parsing the next chunk of text.
    # Each time, the parsers are applied in order of priority, 
    # until a first match is found. This match uses up whatever amount of source
    # text it matched.
    # This is repeated until the source code is all used up.
    def parse
      #puts "\nPARSING text #{@text.inspect} ..."
      while @pos < @text.length do
        #puts "  parsing remaining text #{textNotYetParsed.inspect} ..."
        match = nil
        i = 0
        textToParse = textNotYetParsed
        # Try the specified parsers in order of priority, stopping at the first match
        while i < @parsers.length and not match
          parser = @parsers[i]
          #puts "   trying #{parser[1]} ..."
          match = parser[0].match(textToParse)
          i += 1
        end
        if match then
          send(parser[1], match)
          fullMatchOffsets = match.offset(0)
          #puts " matched at #{fullMatchOffsets.inspect}, i.e. #{textToParse[fullMatchOffsets[0]...fullMatchOffsets[1]].inspect}"
          @pos += fullMatchOffsets[1]
        else
          raise Exception, "No match on #{textNotYetParsed.inspect}"
        end
      end
    end
    
  end
  
  # An error object representing an error in the source code
  class DocumentError < Exception
  end
  
  # An object representing the propositional document which will be created by 
  # passing in source code, and then invoking the parsers to process the source code
  # and output the HTML.
  # The propositional document has three sections:
  # 1. The introduction ("intro")
  # 2. The list of propositions
  # 3. An (optional) appendix
  # The document also keeps track of named and numbered footnotes.
  # The document has three additional required properties, which are "author", "title" and "date".
  
  class PropositionalDocument
    attr_reader :cursor, :fileName
    
    include Helpers
    
    def initialize(properties = {})
      @properties = properties
      @cursor = :intro #where the document is being written to currently
      @intro = []
      @propositions = []
      @appendix = [] 
      @footnoteCount = 0
      @footnoteCountByName = {}
    end
    
    def getNewFootnoteNumberFor(footnoteName)
      @footnoteCount += 1
      footnoteCountString = @footnoteCount.to_s.to_s
      @footnoteCountByName[footnoteName] = footnoteCountString
      return footnoteCountString
    end
    
    def footnoteNumberFor(footnoteName)
      return @footnoteCountByName[footnoteName] || "?"
    end
    
    def checkForProperty(name)
      if not @properties.has_key?(name)
        raise DocumentError, "No property #{name} given for document"
      end
    end
    
    # Check that all the required properties were defined, and that at least one proposition occurred
    def checkIsValid
      checkForProperty("title")
      checkForProperty("author")
      checkForProperty("date")
      if @cursor == :intro
        raise DocumentError, "There are no propositions in the document"
      end
    end
    
    # Dump to stdout (for debugging/tracing)
    def dump
      puts "======================================================="
      puts "Title: #{title.inspect}"
      puts "Author: #{author.inspect}"
      puts "Date: #{date.inspect}"
      puts ""
      if @intro.length > 0 then
        puts "Introduction:"
        for item in @intro do
          puts "  #{item}"
        end
      end
      puts "Propositions:"
      for item in @propositions do
        item.dump("  ")
      end
      if @appendix.length > 0 then
        puts "Appendix:"
        for item in @appendix do
          puts "  #{item}"
        end
      end
      puts "======================================================="
    end
    
    # Call this method in HTML template to write the title (and main heading)
    def title
      return @properties["title"]
    end
    
    # Call this method in HTML template to write the author's name
    def author
      return @properties["author"]
    end
    
    # Call this method in HTML template to show the date
    def date
      return @properties["date"]
    end
    
    # Call this method in HTML template to render the introduction
    def introHtml
      return "<div class=\"intro\">\n#{@intro.map(&:toHtml).join("\n")}\n</div>"
    end
    
    # Call this method in HTML template to render the list of propositions
    def propositionsHtml
      return "<ul class=\"propositions\">\n#{@propositions.map(&:toHtml).join("\n")}\n</ul>"
    end
    
    # Call this method in HTML template to render the appendix
    def appendixHtml
      if @appendix.length == 0 then
        return ""
      else
        return "<div class=\"appendix\">\n#{@appendix.map(&:toHtml).join("\n")}\n</div>"
      end
    end
    
    # Call this method in HTML template to render the 'original link' (for an critique)
    def originalLinkHtml
      if @properties.has_key? "original-link" then
        originalLinkText = @properties["original-link"]
        html = "<div class=\"original-link\">#{processText(originalLinkText)}</div>"
        puts " html = #{html.inspect}"
        return html
      else
        return ""
      end
    end

    # Generate the output HTML using an ERB template file, where the template references
    # the methods title, author, date, propositionsHtml, appendixHtml, originalLinkHtml and fileName
    # (applying them to 'self').
    def generateHtml(templateFileName, fileName)
      @fileName = fileName
      puts "  using template file #{templateFileName} ..."
      templateText = File.read(templateFileName, encoding: 'UTF-8')
      template = ERB.new(templateText)
      @binding = binding
      html = template.result(@binding)
      return html
    end

    # Set a property value on the document
    def setProperty(name, value)
      @properties[name] = value
    end

    # Add a new proposition (only if we are currently in either the introduction or the propositions)
    def addProposition(proposition)
      case @cursor
      when :intro
        @cursor = :propositions
      when :appendix
        raise DocumentError, "Cannot add proposition, already in appendix"
      end
      proposition = PropositionWithExplanation.new(proposition)
      @propositions.push(proposition)
    end
    
    # Start the appendix (but only if we are currently in the propositions)
    def startAppendix
      case @cursor
      when :intro
        raise DocumentError, "Cannot start appendix before any propositions occur"
      when :propositions
        @cursor = :appendix
      when :appendix
        raise DocumentError, "Cannot start appendix, already in appendix"
      end
    end
    
    # Add a textual item, depending on where we are, to the introduction, or the current proposition, 
    # or to the appendix
    def addText(text)
      case @cursor
      when :intro
        @intro.push(text)
      when :propositions
        @propositions[-1].addExplanationItem(text)
      when :appendix
        @appendix.push(text)
      end
    end
    
    # Add a heading (but only to the appendix - note that propositional headings are dealt with separately, 
    # because the heading of a proposition defines a new proposition)
    def addHeading(heading)
      case @cursor
      when :intro
        raise DocumentError, "Headings are not allowed in the introduction"
      when :propositions
        raise DocumentError, "Headings are not allowed in propositions"
      when :appendix
        @appendix.push(heading)
      end
    end
        
    # Special text replacements done after all other processing, 
    # currently just "--" => &ndash;
    def doExtraTextReplacements(text)
      #puts "doExtraTextReplacements on #{text.inspect} ..."
      text.gsub!(/--/m, "&ndash;")
    end
    
    # Process text. "text" can occur in five different contexts:
    # 1. Inside a link (where :weAreInsideALink gets set to true)
    # 2. A proposition
    # 3. A list item
    # 4. A paragraph
    # 5. A secondary heading (i.e. other than a proposition - currently these can only appear in the appendix)
    def processText(text, options = {})
      weAreInsideALink = options[:weAreInsideALink]
      stringBuffer = StringBuffer.new()
      TextBeingProcessed.new(self, text, stringBuffer, weAreInsideALink).parse()
      processedText = stringBuffer.to_string()
      doExtraTextReplacements(processedText)
      return processedText
    end
  
  end
  
  # Base class for top-level document components
  class DocumentComponent
  end
  
  # A document property value definition, such as date = '23 May, 2014'
  class DocumentProperty < DocumentComponent
    def initialize(name, value)
      @name = name
      @value = value
    end
    
    def to_s
      return "DocumentProperty #{@name} = #{@value.inspect}"
    end
    
    # 'write' to the document by setting the specified property value
    def writeToDocument(document)
      document.setProperty(@name, @value)
    end
  end
  
  # Instruction to start the appendix
  class StartAppendix < DocumentComponent
    def to_s
      return "StartAppendix"
    end

    # 'write' to the document by updating document state to being in the appendix
    def writeToDocument(document)
      document.startAppendix
    end
  end
  
  # A proposition (just the heading, without the explanation)
  class Proposition < DocumentComponent
    def initialize(text)
      @text = text
    end
    
    def to_s
      return "Proposition: #{@text.inspect}"
    end
    
    # write to document, by adding a proposition to the document
    # (this will set state to :proposition if we were in the :intro, close any previous proposition, 
    # and start a new one)
    def writeToDocument(document)
      document.addProposition(self)
      @document = document
    end
    
    def toHtml
      return "<div class=\"proposition\">#{@document.processText(@text)}</div>"
    end
  end
  
  # Base text is either a list of list items, or, a paragraph.
  class BaseText < DocumentComponent
    attr_reader :document
    
    # write to document, by adding to the document as a text item. Depending on the
    # current document state, this will be added to the introduction, or to the explanation of the
    # current proposition, or to the appendix
    def writeToDocument(document)
      document.addText(self)
      @document = document
    end
    
    def critiqueClassHtml
      if @isCritique then 
        return " class=\"critique\"" 
      else
        return ""
      end
    end
  end
  
  # A list item (note: this is not a top-level component, rather it is part of an ItemList component)
  class ListItem
    attr_accessor :list
    
    def initialize(text)
      @text = text
      @list = nil
    end
    
    def to_s
      return "ListItem: #{@text.inspect}"
    end
    
    def document
      return list.document
    end
    
    def toHtml
      return "<li>#{document.processText(@text)}</li>"
    end
  end
  
  # A list of list items
  class ItemList < BaseText
    def initialize(options = {})
      @isCritique = options[:isCritique] || false
      @items = []
    end
    
    def addItem(listItem)
      @items.push(listItem)
      listItem.list = self
    end
    
    def to_s
      return "ItemList: #{@items.inspect}"
    end
    
    def toHtml
      return "<ul#{critiqueClassHtml}>\n#{@items.map(&:toHtml).join("\n")}\n</ul>"
    end
  end

  # A paragraph.
  class Paragraph < BaseText
    @@tagsMap = {"bq" => {:tag => "blockquote"}}
    
    def initialize(text, options = {})
      @text = text
      @isCritique = options[:isCritique] || false
      @tag = options[:tag]
      initializeStartEndTags
    end
    
    def initializeStartEndTags
      @tagName = "p"
      className = nil
      if @tag then
        tagDescriptor = @@tagsMap[@tag]
        if tagDescriptor == nil then
          raise DocumentError, "Unknown tag: #{@tag.inspect}"
        end
        @tagName = tagDescriptor[:tag]
        @className = tagDescriptor[:class]
      end
      classNames = []
      if @isCritique then
        classNames.push("critique")
      end
      if @classname then
        classNames.push(@className)
      end
      @startTag = "<#{@tagName}#{classesHtml(classNames)}>"
      @endTag = "</#{@tagName}>"
    end
    
    def classesHtml(classNames)
      if classNames.length == 0 then
        return ""
      else
        return " class=\"#{classNames.join(" ")}\""
      end
    end
    
    def to_s
      return "Paragraph: #{@text.inspect}"
    end
    
    def toHtml
      return "#{@startTag}#{@document.processText(@text)}#{@endTag}"
    end
  end
  
  class Heading < DocumentComponent
    def initialize(text)
      @text = text
    end
    
    def to_s
      return "Heading: #{@text}"
    end
    
    def writeToDocument(document)
      document.addHeading(self)
      @document = document
    end
    
    def toHtml
      return "<h2>#{@document.processText(@text)}</h2>"
    end
  end
  
  class LinesChunk
    attr_reader :lines

    def initialize(line, options = {})
      @lines = [line]
      @isCritique = options[:isCritique] || false
      @tag = options[:tag]
    end
    
    def addLine(line)
      @lines.push(line)
    end
    
    def postProcess
      return self
    end
  end
  
  class SpecialChunk < LinesChunk
    attr_reader :name
    def initialize(name, line)
      super(line)
      @name = name
    end
    
    def to_s
      return "SpecialChunk: (#{name}) #{lines.inspect}"
    end
    
    def isTerminatedBy?(line)
      return (/^\#\#/.match(line) or /^\s*$/.match(line))
    end
    
    def getDocumentComponent
      if name == "appendix"
        return StartAppendix.new()
      else
        return DocumentProperty.new(name, lines.join("\n"))
      end
    end
    
  end
  
  class BlankTerminatedChunk < LinesChunk
    def isTerminatedBy?(line)
      return /^\s*$/.match(line)
    end
    
    def critiqueValue
      if @isCritique then 
        return "(is critique) " 
      else 
        return "" 
      end
    end
  end
  
  class HeadingChunk
    attr_reader :text
    def initialize(text)
      @text = text
    end
    
    def to_s
      return "HeadingChunk: #{text.inspect}"
    end
    
    def getDocumentComponent
      return Heading.new(text)
    end
  end
  
  class ParagraphChunk < BlankTerminatedChunk
    
    def to_s
      return "ParagraphChunk: #{critiqueValue}#{lines.inspect}"
    end
    
    def postProcess
      if lines.length == 2 and lines[1].match(/^[-]+$/) then
        return HeadingChunk.new(lines[0])
      else
        return self
      end
    end
    
    def getDocumentComponent
      return Paragraph.new(lines.join("\n"), :isCritique => @isCritique, :tag => @tag)
    end
  end
  
  class PropositionChunk < BlankTerminatedChunk
    def to_s
      return "PropositionChunk: #{lines.inspect}"
    end
    
    def getDocumentComponent
      return Proposition.new(lines.join("\n"))
    end
  end
  
  class ListChunk < BlankTerminatedChunk
    def to_s
      return "ListChunk: #{critiqueValue}#{lines.inspect}"
    end
    
    def addItemToList(itemList, currentItemLines)
      itemList.addItem(ListItem.new(currentItemLines.join("\n")))
    end
    
    def getDocumentComponent
      itemList = ItemList.new(:isCritique => @isCritique)
      currentItemLines = nil
      for line in lines do
        itemStartMatch = line.match(/^\*\s+(.*)$/)
        if itemStartMatch
          if currentItemLines != nil
            addItemToList(itemList, currentItemLines)
          end
          currentItemLines = [itemStartMatch[1]]
        else
          currentItemLines.push(line.strip)
        end
      end
      if currentItemLines != nil
        addItemToList(itemList, currentItemLines)
      end
      return itemList
    end
  end
  
  class DocumentChunks
    def initialize(srcText)
      @srcText = srcText
    end
    
    def createInitialChunkFromLine(line)
      specialLineMatch = line.match(/^\#\#([a-z\-]*)\s*(.*)$/)
      if specialLineMatch then
        return SpecialChunk.new(specialLineMatch[1], specialLineMatch[2])
      else
        specialTagMatch = line.match(/^\#:([a-z\-0-9]+)\s*(.*)$/)
        if specialTagMatch then
          return ParagraphChunk.new(specialTagMatch[2], :tag => specialTagMatch[1])
        else
          propositionMatch = line.match(/^\#\s*(.*)$/)
          if propositionMatch then
            return PropositionChunk.new(propositionMatch[1])
          else
            critiqueMatch = line.match(/^\?\?\s(.*)$/)
            isCritique = critiqueMatch != nil
            if isCritique then
              line = critiqueMatch[1]
            end
            listMatch = line.match(/^\*\s+/)
            if listMatch then
              return ListChunk.new(line, :isCritique => isCritique)
            else
              blankLineMatch = line.match(/^\s*$/)
              if blankLineMatch then
                return nil
              else
                return ParagraphChunk.new(line, :isCritique => isCritique)
              end
            end
          end
        end
      end
    end
    
    def each
      currentChunk = nil
      for line in @srcText.split("\n") do
        if currentChunk == nil then
          currentChunk = createInitialChunkFromLine(line)
        else
          if currentChunk.isTerminatedBy?(line)
            yield currentChunk.postProcess
            currentChunk = createInitialChunkFromLine(line)
          else
            currentChunk.addLine(line)
          end
        end
      end
      if currentChunk
        yield currentChunk.postProcess
      end
    end
  end
  
  class Propolizer
    
    # Main method to generated the HTML document from the provided source text
    def propolize(templateFileName, srcText, fileName, properties = {})
      document = PropositionalDocument.new(properties)
      for chunk in DocumentChunks.new(srcText) do 
        #puts "#{chunk}"
        component = chunk.getDocumentComponent
        #puts " => #{component}"
        component.writeToDocument(document)
      end
      document.checkIsValid()
      #document.dump
      
      return document.generateHtml(templateFileName, File.basename(fileName))
    end
  end
end
