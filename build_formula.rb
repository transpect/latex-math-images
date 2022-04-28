#!/usr/bin/ruby
# -*- coding: utf-8 -*-

require 'optparse'
require 'open3'
require 'json'

SCRIPTDIR = File.expand_path(File.dirname(__FILE__))
LATEXDIR = "#{SCRIPTDIR}/latex"

class Options
  Version = '0.9.0'

  class ScriptOptions
    attr_accessor :iname, :iext, :ipath,
                  :oname, :oext, :opath,
                  :mname, :mext, :mpath,
                  :logfile,
                  :mmlname, :mmlext, :mmlpath,
                  :verbose, :debug, :silent,
                  :tempdir,
                  :engine, :texbin, :gsbin,
                  :epsMeta,
                  :addsource

    ## default values
    def initialize
      self.iname = "formula"
      self.iext = ".tex"
      self.ipath = SCRIPTDIR
      self.oname = "formula"
      self.oext = ".eps"
      self.opath = SCRIPTDIR
      self.mext = ".json"
      self.mname = "formula"
      self.mpath = SCRIPTDIR

      self.tempdir = "#{SCRIPTDIR}/temp"
      self.engine = "latex"
      self.texbin = getDefaultBin("latex")
      self.gsbin = getDefaultBin("gs")

      self.epsMeta = false
      self.addsource = false

      self.verbose = false
      self.debug = false
      self.silent = false
    end # method initialize

    def getDefaultBin(command)
      return out = `which #{command}`.gsub(/^(.*)\/+#{command}\n*$/, '\1')
    end

    def define_options(parser)
      parser.banner = "#{parser.program_name} version #{Version}\nUsage: build_formula.rb [options] style"
      parser.separator ""
      parser.separator "Mandatory arguments:"
      parser.separator "  style\t\tis the basename of the publisher's style sheet. This file has to be found in the 'styles/' subfolder."
      parser.separator ""
      parser.separator "Specific options:"

      # add additional options
      parser.on("-iFILE", "--input FILE",
                "FILE that contains the math code to be rendered",
                "  default: formula.tex.") do |file|
        absfile = File.expand_path(file)
        self.ipath = File.dirname(absfile)
        self.iname = File.basename(absfile, ".*")
        if File.extname(absfile) != ""
          self.iext = File.extname(absfile)
        end
      end

      parser.on("-MFILE", "--mathml FILE",
                "Name of the MathML input file",
                "  default: [none]") do |file|
        absfile = File.expand_path(file)
        self.mmlpath = File.dirname(absfile)
        self.mmlname = File.basename(absfile, '.*')
        if File.extname(absfile) != ""
          self.mmlext = File.extname(absfile)
        end
      end
      parser.separator ""
      parser.separator "Output control:"

      parser.on("-oFILE", "--output FILE",
                "Name of the output file",
                "  default: formula.eps.",
                "    When the extension is omitted, `eps' is used. Otherwise, the file is ",
                "    converted to the image format of the extension.",
                "    ",
                "    Supported output formats and used gs devices:",
                "      eps, ps, pdf - epswrite",
                "      jpg, jpeg    - jpeggray",
                "      png          - pnggray"
               ) do |file|
        absfile = File.expand_path(file)
        self.opath = File.dirname(absfile)
        self.oname = File.basename(absfile, ".*")
        if File.extname(absfile) != ""
          self.oext = File.extname(absfile)
        end
      end

      parser.on("-mFILE", "--meta-out FILE",
                "Name of the meta file",
                "  default: formula.json.") do |file|
        absfile = File.expand_path(file)
        self.mpath = File.dirname(absfile)
        self.mname = File.basename(absfile, '.*')
        if File.extname(absfile) != ""
          self.mext = File.extname(absfile)
        end
      end

      parser.on("-lFILE", "--log FILE",
                "Name of the LaTeX log file") do |file|
        self.logfile = File.expand_path(file)
      end

      parser.on("-E", "--eps-meta", "Write meta data as comment into the eps output", "  requires output format to be eps!") { |x| self.epsMeta = true }
      parser.on("-S", "--add-source", "Include TeX/MathML source in JSON output", "  may be problematic due to escaping or multilines") { |x| self.addsource = true }
      parser.on("-tTEMP", "--temp_dir TEMP", "Temporary working directory") { |x| self.tempdir = x }

      parser.separator ""
      parser.separator "LaTeX Options:"
      parser.on("-eENGINE", "--tex-engine ENGINE", "TeX Engine", "  default: latex") { |x| self.engine = x }
      parser.on("-TTEXBIN", "--tex-bin TEXBIN", "TeX binary path", "  defaults to where-ever `whereis latex' points to.") { |x| self.texbin = x }
      parser.on("-gGSBIN", "--gs-bin GSBIN", "GhostScript binary path", "  defaults to where-ever `whereis gs' points to.") { |x| self.gsbin = x }

      parser.separator ""
      parser.separator "Shell output control:"
      parser.on("-V", "--verbose", "Extensive output") { |x| self.verbose = true }
      parser.on("-d", "--debug", "Debugging on") { |x| self.debug = true }
      parser.on("-s", "--silent", "No output at all") { |x| self.silent = true }

      parser.separator ""
      parser.separator "Common options:"
      # No argument, shows at tail.  This will print an options summary.
      parser.on_tail("-h", "--help", "Show this message") { puts parser ; exit(0) }
      parser.on_tail("-v", "--version", "Show version") { puts "#{parser.program_name} Version #{Version}" ; exit(0) }
    end # method define_options
  end # class ScriptOptions


  #
  # Return a structure describing the options.
  #
  def parse(args)
    # The options specified on the command line will be collected in
    # *options*.

    @options = ScriptOptions.new
    @args = OptionParser.new do |parser|
      parser.program_name = "le-tex Formula Generator"
      @options.define_options(parser)
      begin
        parser.parse!(args)
      rescue OptionParser::InvalidOption => inv
        inv = inv.to_s.sub(/invalid option:\s+/,'')
        puts "Warning: Unknown option #{inv}"
      end
    end
    @options
  end # method parse
 attr_reader :parser, :options
end  # class Options



class FormulaBuilder
  attr_accessor :options, :optParser, :style,
                :input, :texinput, :mathSource, :mmlSource, :json,
                :ofile, :mfile,
                :cmd, :texopt, :texbin, :gsbin, :device

  def initialize
    self.optParser = Options.new
    self.options = optParser.parse(ARGV)

    self.ofile = "#{@options.opath}/#{@options.oname}#{@options.oext}"
    self.mfile = "#{@options.mpath}/#{@options.mname}#{@options.mext}"

    checkStyle(ARGV[0])
    checkInput()
    checkEPS() if @options.epsMeta
    prepareTexOpt()
    setDevices()

    self.cmd = "umask 002; cd #{@options.tempdir} ; #{@texinput} ; "
    self.gsbin = "#{@options.gsbin}/gs"

    prepareTemp()
  end # method initialize


  def setDevices()
    devices = {
      ".eps"  => "eps2write",
      ".ps"   => "eps2write",
      ".pdf"  => "eps2write",
      ".png"  => "pnggray -r1200 -dDownScaleFactor=2 -dUseCropBox",
      ".jpg"  => "jpeggray -r1200 -dDownScaleFactor=2 -dUseCropBox",
      ".jpeg" => "jpeggray -r1200 -dDownScaleFactor=2 -dUseCropBox"
    }
    if devices[@options.oext]
      self.device = devices[@options.oext]
      puts "Device: #{@device} (#{@options.oext} of #{devices})" if @options.debug
    else
      error("File extension `#{@options.oext}' not supported.", true)
    end
  end

  def prepareTemp ()
    clearTemp()
    `umask 002 ; mkdir #{@options.tempdir}` unless Dir.exists?(@options.tempdir)
    `umask 002 ; cp #{LATEXDIR}/standalone.cls #{@options.tempdir}/`
    `umask 002 ; cp #{LATEXDIR}/mathfig.sty #{@options.tempdir}/`
    prepareTeXTemplate()
  end # method prepareTemp

  def clearTemp(dbg = false)
    unless dbg
      `rm -rf #{@options.tempdir}`
    end
  end # method clearTemp

  def runTeX()
    self.texbin = "#{@options.texbin}/#{@options.engine}"
    case @options.engine
    when "latex"
      runLatex()
    when "pdflatex"
      runPDFlatex()
    when "lualatex"
      runLualatex()
    end
    writeMeta()
  end

  private

  def writeMeta()
    jsn = "#{@options.tempdir}/template.json"
    if File.exists?(jsn)
      self.json = JSON.parse(File.read(jsn))
      if @options.addsource
        @json["tex"] = @mathSource if @mathSource
        @json["mml"] = @mmlSource if @mmlSource
      end
      log = File.read("#{@options.tempdir}/template.log")
      if @options.logfile
        File.open(@options.logfile, "w") { |x| x.write(log) }
      end
      if log.match(/Error/)
        @json["status"] = "error"
      else
        @json["status"] = "success"
      end
      File.open(@mfile, "w") { |x| x.write(JSON.pretty_generate(@json)) }
      writeMetaEPS() if @options.epsMeta
    else
      error("Temporary json file  `#{@json}' does not exist!")
    end
  end

  def writeMetaEPS()
    eps = File.read(@ofile).split(/^%%EndComments/)
    mout = ""
    for meta in @json
      src = meta[1].gsub(/\n/, "\n%%")
      mout += "%%#{meta[0]}: #{src}\n"
    end
    neweps = "#{eps[0]}#{mout}%%EndComments#{eps[1]}"
    File.open(@ofile, "w").write(neweps)
  end

  def prepareTexOpt()
    if @options.debug
      self.texopt = ""
    else
      self.texopt = "--interaction=nonstopmode"
    end
    self.texinput = "export TEXINPUTS=.:#{SCRIPTDIR}/styles/#{@style}/: "
    self.texinput += "; export TTFONTS=.:#{SCRIPTDIR}/styles/#{@style}/: "
  end

  def runLatex()
    print "Running latex..." unless @options.silent
    lcmd = "#{@cmd} #{@texbin} #{@texopt} template.tex ; #{@options.texbin}/dvips -E* template.dvi"
    doRunLaTeX(lcmd)
    puts "\t\t\tdone." unless @options.silent
    patchFonts("ps")
    # patchBBox("gs -q -dNOCACHE -dNOPAUSE -dBATCH -dSAFER -dEPSCrop -sDEVICE=bbox template.dvi")
  end

  def runPDFlatex()
    print "Running pdflatex..." unless @options.silent
    pdfcmd = @cmd + "#{@texbin} #{@texopt} template.tex "
    puts "\t\t\tdone." unless @options.silent
    runpdfout(pdfcmd)
  end

  def runLualatex()
    print "Running lualatex..." unless @options.silent
    luacmd = @cmd + "#{@texbin} #{@texopt} template.tex "
    puts "\t\t\tdone." unless @options.silent
    runpdfout(luacmd)
  end

  def runpdfout(pdfcmd)
    doRunLaTeX(pdfcmd)
    patchFonts("pdf")
  end

  def patchFonts(suffix)
    print "Embedding fonts..." unless @options.silent
    doRunLaTeX(@cmd + "#{@gsbin} -dNOPAUSE -dBATCH -dNOCACHE -dEPSCrop -dCompatibilityLevel=1.4 -dPDFSETTINGS=/screen -dPDFSETTINGS=/prepress -dCompressFonts=true  -dSubsetFonts=true -dEmbedAllFonts=true -sDEVICE=pdfwrite -sOutputFile=template_emb.pdf -f template.#{suffix}")
    puts "\t\t\tdone." unless @options.silent
    convertOutput()
    # patchBBox("gs -q -dNOCACHE -dNOPAUSE -dBATCH -dSAFER -sDEVICE=bbox -sOutputFile=\"#{ofile}-temp\" template.pdf")
  end

  def convertOutput()
    print "Converting output to #{@options.oext}..." unless @options.silent
    doRunLaTeX(@cmd + "#{@gsbin}  -dNOCACHE -dNOPAUSE -dBATCH -dSAFER -sDEVICE=#{@device} -sFONTDIR=\"#{SCRIPTDIR}/styles/#{@style}/\" -sOutputFile=\"#{ofile}\" template_emb.pdf ")
    puts "\t\tdone."
  end

  def patchBBox(gs)
    bbox = `#{@cmd} #{gs} 2>&1`
    `rm #{ofile}-temp` if File.exists?("#{ofile}-temp")
    cnts = IO.read(@ofile).gsub(/%%BoundingBox: [0-9.-]+ [0-9.-]+ [0-9.-]+ [0-9.-]+\n%%HiResBoundingBox: [0-9.-]+ [0-9.-]+ [0-9.-]+ [0-9.-]+\n/, bbox)
    File.open(@ofile, "w") { |f| f.puts cnts }
    File.chmod(0775, @ofile)
  end

  def doRunLaTeX(cmd)
    puts "executing:\n  #{cmd}" if @options.debug
    if @options.verbose or @options.debug
      system(cmd)
    else
      system(cmd, :err => File::NULL, :out => File::NULL)
    end
  end

  def checkEPS()
    error("--eps-meta flag is set, but output format is not EPS!") unless @options.oext == ".eps"
  end

  def checkInputVal(input, str)
    if File.exists?(input)
      file = IO.read(input)
      if file == ""
        error("#{str} input file \"#{input}\" seems to be empty!")
      else
        return file
      end
    else
      error("#{str} input file \"#{@input}\" not found!")
    end
  end

  def checkInput()
    self.input = "#{@options.ipath}/#{@options.iname}#{@options.iext}"
    self.mathSource = checkInputVal(@input, "TeX ")
    self.mmlSource = checkInputVal("#{@options.mmlpath}/#{@options.mmlname}#{@options.mmlext}", "MathML") if @options.mmlname
  end

  def checkStyle(sty)
    if sty
      if File.exists?("#{SCRIPTDIR}/styles/#{sty}/#{sty}.sty")
        self.style = sty
      else
        error("Style `#{SCRIPTDIR}/styles/#{sty}/#{sty}.sty' does not exist!")
      end
    else
      error("No style given!", true)
    end
  end # method checkStyle

  def prepareTeXTemplate()
    template = IO.read("#{SCRIPTDIR}/latex/template.tex")
    template = template.gsub(/<style>/, @style)
    template = template.gsub(/<input>/, @mathSource.gsub(/\\\\/, "\\\\\\\\\\\\")) # grummel ò.ó
    temp_template = "#{@options.tempdir}/template.tex"
    File.open(temp_template, "w+") { |f| f.puts template }
    File.chmod(0775, temp_template)
  end # method prepareTeXTemplate

  def show_help()
    optParser.parse(["-h"])
  end # method show_help

  def error(msg, showhelp=false)
    begin
      raise msg
    rescue
      puts "ERROR: #{$!.message}\n\n"
      if showhelp
        show_help()
      end
      exit(1)
    end
  end # method error

end # class FormulaBuilder

builder = FormulaBuilder.new
builder.runTeX()
builder.clearTemp(builder.options.debug)

# p ARGV
# puts "Output:\t#{builder.options.inspect}"

