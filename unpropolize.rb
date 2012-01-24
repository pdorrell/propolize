
class Unpropolizer
  def initialize
    @initString = "<div class=\"propositional\">"
    @critiqueInitString = "<div class=\"propositional critique\">"
    @endString = "<div class=\"endnote\">"
    @titleReplacement = [/\<h1>([^<]*)\<\/h1>\n+/, "##title \\1\n"]
    @creditReplacement = [/\<div class="credit">([^,]*), ([^<]*)\<\/div>/, 
                         "##author \\1\n##date \\2"]
    @eolnWhitespaceReplacement = [/[ ]*\n/, "\n"]
    @multipleEmptyLineReplacement = [/\n\n\n*/, "\n\n"]
    @paragraphReplacement = [/\<p>\n*/, "\n"]
    @critiqueParagraphReplacement = [/\<p class=\"critique\">\n*/, "\n?? "]
    @originalLinkReplacement = [/\<div class=\"original-link\">\n*/, "##original-link "]
    @italicStartReplacement = [/\<i>/, "*"]
    @italicEndReplacement = [/\<\/i>/, "*"]
    @boldStartReplacement = [/\<b>/, "**"]
    @boldEndReplacement = [/\<\/b>/, "**"]
    @footnoteLinkReplacement = [/\<a href="\#([^"]*)" class=\"footnote\">([^<]*)\<\/a>/, 
                                "[::](\\1::)"]
    @anchorLinkReplacement = [/\<a href="\#([^"]*)">([^<]*)\<\/a>/, 
                              "[\\2](\\1:)"]
    @linkReplacement = [/\<a href="([^"]*)">([^<]*)\<\/a>/, 
                        "[\\2](\\1)"]
    @footnoteAnchorReplacement = [/\<span class=\"footnoteNumber\">\d*\<\/span>\<a name="([^"]*)">/, 
                                  "[\\1::]"]
    @anchorReplacement = [/\<a name="([^"]*)">/, 
                          "[\\1:]"]
    @listReplacement = [/\<ul>/, "\n\n"]
    @listItemReplacement = [/\n[ ]*\<li>/, "\n* "]
    @ndashReplacement = ["&ndash;", "--"]
    @appendixReplacement = ["<div class=\"appendix\">", "##appendix\n\n"]
    @h2Replacement = ["<h2>", "\n"]
    @h2EndReplacement = ["</h2>", "\n---------------"]
    
    @propositionReplacement = [/\<li>\s*\<div class="proposition">/, 
                               "# "]
    
    @templateNameReplacement = [/\<!-- template:\s*([^\s]*) -->/m, 
                                "##template \\1"]

    @singleReplacements = [@titleReplacement, @creditReplacement, @templateNameReplacement]
    @multiReplacements = [@paragraphReplacement, @critiqueParagraphReplacement, 
                          @originalLinkReplacement, 
                          @italicStartReplacement, @italicEndReplacement, 
                          @boldStartReplacement, @boldEndReplacement, 
                          @anchorLinkReplacement, @linkReplacement, 
                          @footnoteAnchorReplacement, @anchorReplacement, 
                          @footnoteLinkReplacement, 
                          @propositionReplacement, 
                          @listReplacement, @listItemReplacement, 
                          @ndashReplacement, @appendixReplacement, 
                          @h2Replacement, @h2EndReplacement]

    @patternsToRemove = [/\<div class="intro">/, /\<\/[a-zA-Z]+>/,
                         /\<ul class="propositions">/]
    
    @finalFixups = [@eolnWhitespaceReplacement, @multipleEmptyLineReplacement]
  end
  
  def stripStartAndEnd(srcHtml)
    outputText = srcHtml
    initPartitioned = outputText.partition(@initString)
    isCritique = false
    if initPartitioned[1] == "" then
      initPartitioned = outputText.partition(@critiqueInitString)
      if initPartitioned[1] == "" then
        raise "initial string #{@initString} or #{@critiqueInitString} not found in HTML"
      end
      isCritique = true
    end
    outputText = initPartitioned[2]
    endPartitioned = outputText.partition(@endString)
    if endPartitioned[1] == "" then 
      raise "end string #{@endString} not found in HTML"
    end
    outputText = endPartitioned[0]
    return [outputText, isCritique]
  end
  
  def unpropolize(srcHtml)
    outputTextAndIsCritiqued = stripStartAndEnd(srcHtml)
    outputText = outputTextAndIsCritiqued[0]
    isCritiqued = outputTextAndIsCritiqued[1]
    outputText.lstrip!()
    if isCritiqued then
      outputText = "##critique\n" + outputText
    end
    for replacement in @singleReplacements do
      outputText.sub!(replacement[0], replacement[1])
      #puts "now outputText (replacing with #{replacement[1].inspect})= #{outputText.inspect}"
    end
    for replacement in @multiReplacements do
      outputText.gsub!(replacement[0], replacement[1])
      #puts "now outputText (replacing with #{replacement[1].inspect})= #{outputText.inspect}"
    end
    for patternToRemove in @patternsToRemove do
      outputText.gsub!(patternToRemove, "")
      #puts "now outputText after removing #{patternToRemove.inspect}, = #{outputText.inspect}"
    end
    for replacement in @finalFixups do
      outputText.gsub!(replacement[0], replacement[1])
      #puts "now outputText (replacing with #{replacement[1].inspect})= #{outputText.inspect}"
    end
    return outputText
  end
  
  def unpropolizeFile(srcFile, outFile)
    puts "Processing source file #{srcFile} ..."
    srcHtml = File.read(srcFile, encoding: 'UTF-8')
    outputText = unpropolize(srcHtml)
    outputFile = File.new(outFile, "w", encoding: 'UTF-8')
    outputFile.write(outputText)
    outputFile.close
    puts " output written to file #{outFile} ..."
    firstLessThanIndex = outputText.index("<")
    if firstLessThanIndex then
      stringExtract = outputText[firstLessThanIndex, 100]
      raise Exception, "'<' character found at #{stringExtract}"
    end
  end
end

def processFiles(filesToProcess, srcDir, outDir)
  for fileName in filesToProcess do
    srcFile = File.join(srcDir, fileName)
    outFile = File.join(outDir, fileName.sub(/[.]html$/, ".propositional"))
    unpropolizer = Unpropolizer.new()
    unpropolizer.unpropolizeFile(srcFile, outFile)
  end
end

def main
  begin
    # ./propolize-test-config.rb is not checked into Git ... you can create your own that defines srcDir & outDir
    require './propolize-test-config'
    outDir = PropolizeTestConfig.srcDir
    srcDir = PropolizeTestConfig.outDir

    allFiles = []
    Dir.glob("#{srcDir}/**/*.html").each  do |f|
      allFiles.push(f[(srcDir.length+1)..f.length])
    end

    filesToProcess = allFiles
    puts "filesToProcess = #{filesToProcess.inspect}"
    processFiles(filesToProcess, srcDir, outDir)
  rescue LoadError
    puts "LoadError: required file./propolize-test-configs not found"
  end
end

main
