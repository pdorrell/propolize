require 'erb'

def html_escape(s)
  s.to_s.gsub(/&/, "&amp;").gsub(/>/, "&gt;").gsub(/</, "&lt;")
end

def h(s)
  html_escape(s)
end

module Propolize

  class StringBuffer
    # a very simple string buffer
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
  
  class PropositionWithExplanation
    def initialize(proposition)
      @proposition = proposition
      @explanationItems = []
    end
    
    def addExplanationItem(item)
      @explanationItems.push(item)
    end
    
    def dump(indent)
      puts ("#{indent}#{@proposition}")
      for item in @explanationItems do
        puts ("#{indent}  #{item}")
      end
    end
    
    def toHtml
      return "<li>\n#{@proposition.toHtml}\n#{@explanationItems.map(&:toHtml).join("\n")}\n</li>"
    end
    
  end
  
  class TextBeingProcessed
    @@plainTextParser = [/\A[^\\\*\[&]+/m, :processPlainText]
    @@backslashParser = [/\A\\(.)/m, :processBackslash]
    @@entityParser = [/\A&(([A-Za-z0-9]+)|(#[0-9]+));/m, :processEntity]
    @@doubleAsterixParser = [/\A\*\*/m, :processDoubleAsterix]
    @@singleAsterixParser = [/\A\*/m, :processSingleAsterix]
    @@linkOrAnchorParser = [/\A\[([^\]]*)\](\(([^\)]+)\)|)/m, :processLinkOrAnchor]

    @@linkTextParsers = [@@plainTextParser, @@backslashParser, @@entityParser, 
                         @@doubleAsterixParser, @@singleAsterixParser]
    
    @@fullTextParsers = @@linkTextParsers + [@@linkOrAnchorParser]
    
    def initialize(document, text, writer, linkText)
      @document = document
      @text = text
      @writer = writer
      @pos = 0
      @italic = false
      @bold = false
      @parsers = if linkText then @@linkTextParsers else @@fullTextParsers end
    end
    
    def processPlainText(match)
      @writer.write(html_escape(match[0]))
    end
    
    def processBackslash(match)
      @writer.write(html_escape(match[1]))
    end
    
    def processEntity(match)
      @writer.write(match[0])
    end
    
    def processDoubleAsterix(match)
      if @bold then
        @writer.write("</b>")
        @bold = false
      else
        @writer.write("<b>")
        @bold = true
      end
    end
    
    def processSingleAsterix(match)
      if @italic then
        @writer.write("</i>")
        @italic = false
      else
        @writer.write("<i>")
        @italic = true
      end
    end
    
    def processLink (text, url)
      anchorMatch = /^([^\/:]*):$/.match(url)
      footnoteMatch = /^([^\/:]*)::$/.match(url)
      linkTextHtml = @document.processText(text, :linkText => true)
      if footnoteMatch then 
        footnoteName = footnoteMatch[1]
        footnoteNumber = @document.getNewFootnoteNumberFor(footnoteName)
        @writer.write("<a href=\"##{footnoteName}\" class=\"footnote\">#{footnoteNumber}</a>")
      elsif anchorMatch then
        @writer.write("<a href=\"##{anchorMatch[1]}\">#{linkTextHtml}</a>")
      else
        @writer.write("<a href=\"#{url}\">#{linkTextHtml}</a>")
      end
    end
    
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
    
    def processLinkOrAnchor(match)
      if match[3] then
        processLink(match[1], match[3])
      else
        processAnchor(match[1])
      end
    end
    
    def checkValidAtEnd
      if @bold then
        raise DocumentError, "unclosed bold span"
      end
      if @italic then
        raise DocumentError, "unclosed italic span"
      end
    end
    
    def textNotYetParsed
      return @text[@pos..-1]
    end
    
    def parse
      #puts "\nPARSING text #{@text.inspect} ..."
      while @pos < @text.length do
        #puts "  parsing remaining text #{textNotYetParsed.inspect} ..."
        match = nil
        i = 0
        textToParse = textNotYetParsed
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
  
  class DocumentError<Exception
  end
  
  class PropositionalDocument
    attr_reader :cursor, :fileName
    
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
    
    def checkIsValid
      checkForProperty("title")
      checkForProperty("author")
      checkForProperty("date")
      #checkForProperty("template")
      if @cursor == :intro
        raise DocumentError, "There are no propositions in the document"
      end
    end
    
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
    
    def title
      return @properties["title"]
    end
    
    def author
      return @properties["author"]
    end
    
    def date
      return @properties["date"]
    end
    
    def templateName
      return @properties["template"]
    end
    
    def introHtml
      return "<div class=\"intro\">\n#{@intro.map(&:toHtml).join("\n")}\n</div>"
    end
    
    def propositionsHtml
      return "<ul class=\"propositions\">\n#{@propositions.map(&:toHtml).join("\n")}\n</ul>"
    end
    
    def appendixHtml
      if @appendix.length == 0 then
        return ""
      else
        return "<div class=\"appendix\">\n#{@appendix.map(&:toHtml).join("\n")}\n</div>"
      end
    end
    
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
    
    def generateHtml(baseRelativeUrl, srcDir, fileName)
      @baseRelativeUrl = baseRelativeUrl
      @srcDir = srcDir
      @fileName = fileName
      templateFileName = File.join(@srcDir, "#{templateName}.html.erb")
      puts "  using template file #{templateFileName} ..."
      templateText = File.read(templateFileName, encoding: 'UTF-8')
      template = ERB.new(templateText)
      @binding = binding
      html = template.result(@binding)
      return html
    end
    
    def generateHtmlFromTemplate(baseRelativeUrl, templateFileName, fileName)
      @baseRelativeUrl = baseRelativeUrl
      @fileName = fileName
      puts "  using template file #{templateFileName} ..."
      templateText = File.read(templateFileName, encoding: 'UTF-8')
      template = ERB.new(templateText)
      @binding = binding
      html = template.result(@binding)
      return html
    end
    
    def setProperty(name, value)
      @properties[name] = value
    end

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
        
    def doExtraTextReplacements(text)
      #puts "doExtraTextReplacements on #{text.inspect} ..."
      text.gsub!(/--/m, "&ndash;")
    end
    
    def processText(text, options = {})
      linkText = options[:linkText]
      stringBuffer = StringBuffer.new()
      TextBeingProcessed.new(self, text, stringBuffer, linkText).parse()
      processedText = stringBuffer.to_string()
      doExtraTextReplacements(processedText)
      return processedText
    end
  
  end
  
  class DocumentProperty
    def initialize(name, value)
      @name = name
      @value = value
    end
    
    def to_s
      return "DocumentProperty #{@name} = #{@value.inspect}"
    end
    
    def writeToDocument(document)
      document.setProperty(@name, @value)
    end
  end
  
  class StartAppendix
    def to_s
      return "StartAppendix"
    end
    
    def writeToDocument(document)
      document.startAppendix
    end
  end
  
  class Proposition
    def initialize(text)
      @text = text
    end
    
    def to_s
      return "Proposition: #{@text.inspect}"
    end
    
    def writeToDocument(document)
      document.addProposition(self)
      @document = document
    end
    
    def toHtml
      return "<div class=\"proposition\">#{@document.processText(@text)}</div>"
    end
  end
  
  class BaseText
    attr_reader :document
    
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
  
  class ItemList<BaseText
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
  
  
  
  class Paragraph<BaseText
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
  
  class Heading
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
  
  class SpecialChunk<LinesChunk
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
  
  class BlankTerminatedChunk<LinesChunk
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
  
  class ParagraphChunk<BlankTerminatedChunk
    
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
  
  class PropositionChunk<BlankTerminatedChunk
    def to_s
      return "PropositionChunk: #{lines.inspect}"
    end
    
    def getDocumentComponent
      return Proposition.new(lines.join("\n"))
    end
  end
  
  class ListChunk<BlankTerminatedChunk
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
    
    def highLevelParse(lines)
      for line in lines do
        yield "parsed #{line}"
      end
    end
    
    def propolize(srcDir, srcText, baseRelativeUrl, fileName)
      document = PropositionalDocument.new
      for chunk in DocumentChunks.new(srcText) do 
        #puts "#{chunk}"
        component = chunk.getDocumentComponent
        #puts " => #{component}"
        component.writeToDocument(document)
      end
      document.checkIsValid
      #document.dump
      
      return document.generateHtml(baseRelativeUrl, srcDir, fileName)
    end
    
    def propolizeUsingTemplate(templateFileName, srcText, baseRelativeUrl, fileName, properties = {})
      baseRelativeUrl ||= ""
      document = PropositionalDocument.new(properties)
      for chunk in DocumentChunks.new(srcText) do 
        #puts "#{chunk}"
        component = chunk.getDocumentComponent
        #puts " => #{component}"
        component.writeToDocument(document)
      end
      document.checkIsValid()
      #document.dump
      
      return document.generateHtmlFromTemplate(baseRelativeUrl, templateFileName, fileName)
    end
    
    def propolizeFile(srcFileName, baseRelativeUrl, outFileName)
      puts "Processing source file #{srcFileName} ..."
      srcDir = File.dirname(srcFileName)
      srcText = File.read(srcFileName, encoding: 'UTF-8')
      htmlOutput = propolize(srcDir, srcText, baseRelativeUrl, File.basename(outFileName))
      puts "  writing output to #{outFileName} ..."
      outFile = File.new(outFileName, "w", encoding: 'UTF-8')
      outFile.write(htmlOutput)
      outFile.close
    end
  end
end

def processFiles(filesToProcess, srcDir, baseRelativeUrl, outDir)
  for baseSrcFileName in filesToProcess do
    srcFileName = File.join(srcDir, baseSrcFileName)
    outFileName = File.join(outDir, baseSrcFileName.sub(/[.]propositional$/, ".html"))
    propolizer = Propolize::Propolizer.new()
    propolizer.propolizeFile(srcFileName, baseRelativeUrl, outFileName)
  end
end

def mainNoArgs
  begin
    # ./propolize-test-config.rb is not checked into Git ... you can create your own that defines srcDir & outDir
    require './propolize-test-config'
    srcDir = PropolizeTestConfig.srcDir
    outDir = PropolizeTestConfig.outDir
    baseRelativeUrl = "../"
    
    allFiles = []
    
    Dir.glob("#{srcDir}/**/*.propositional").each  do |f|
      allFiles.push(f[(srcDir.length+1)..f.length])
    end
  
    filesToProcess = allFiles
  
    processFiles(filesToProcess, srcDir, baseRelativeUrl, outDir)
  rescue LoadError
    puts "LoadError: required file./propolize-test-configs not found"
  end
end

def propolizeFile(srcFileName, relativeOutputDir, baseRelativeUrl)
  puts "Propolizing file #{srcFileName} into relativeOutputDir #{relativeOutputDir} ..."
  srcDirName = File.dirname(srcFileName)
  baseFileName = File.basename(srcFileName)
  outputDirName = File.join(srcDirName, relativeOutputDir)
  processFiles([baseFileName], srcDirName, baseRelativeUrl, outputDirName)
end
