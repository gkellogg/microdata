#! /usr/bin/env ruby
# Parse test manifest to create driver and area-specific test manifests
#
# Manifest has the following columns:
#
#  * test - test number, used for naming test files, in the form "testnnn" the test manifest
#  * name - name of the test, used for mf:name on the test entry
#  * comment
#    description of the test, used for rdfs:comment on the test entry
#  * approval - Approval status of the test, one of rdft:Approved, rdft:Proposed, or rdft:Rejected.
#  * rdfa - TRUE or FALSE indicating if an RDFa Evaluation Test is generated
#  * json - TRUE or FALSE indicating if a JSON Evaluation Test is generated
#  * test-type - if FALSE, all tests are Negative tests.

require 'getoptlong'
require 'csv'
require 'json'
require 'haml'
require 'fileutils'

class Manifest
  JSON_STATE = JSON::State.new(
    :indent       => "  ",
    :space        => " ",
    :space_before => "",
    :object_nl    => "\n",
    :array_nl     => "\n"
  )

  TITLE = {
    json: "Microdata JSON tests",
    rdfa: "Microdata RDFa Tests",
  }
  DESCRIPTION = {
    json: "Tests transformation of Microdata to JSON.",
    rdfa: "Tests transformation of Microdata to RDFa.",
  }
  EXTENTIONS = {
    json: 'json',
    rdfa: 'rdfa',
    rdf: 'ttl',
  }
  attr_accessor :prefixes, :terms, :properties, :classes, :instances, :datatypes

  Test = Struct.new(:id, :name, :comment, :approval, :option, :action, :result_rdfa, :result_json)

  attr_accessor :tests

  def initialize
    csv = CSV.new(File.open(File.expand_path("../manifest.csv", __FILE__)))
    @prefixes, @terms, @properties, @classes, @datatypes, @instances = {}, {}, {}, {}, {}, {}

    columns = []
    csv.shift.each_with_index {|c, i| columns[i] = c.to_sym if c}

    @tests = csv.select {|l| l[0]}.map do |line|
      entry = {}
      # Create entry as object indexed by symbolized column name
      line.each_with_index {|v, i| entry[columns[i]] = v ? v.gsub("\r", "\n").gsub("\\", "\\\\") : nil}

      extras = entry[:extra].to_s.split(/\s+/).inject({}) do |memo, e|
        k, v = e.split("=", 2)
        v = v[1..-2] if v =~ /^".*"$/
        memo[k.to_sym] = v.include?(',') ? v.split(',') : v
        memo
      end
      extras[:rdfa] = entry[:rdfa] unless entry[:rdfa] == "FALSE"
      extras[:json] = entry[:json] unless entry[:json] == "FALSE"
      test = Test.new(entry[:test], entry[:name], entry[:comment], entry[:approval], extras)

      test.action = extras.fetch(:action) {"#{test.id}.html"}
      test.result_rdfa  = "#{test.id}.rdfa" if test.option[:rdfa] && test.option[:rdfa] != "FALSE"
      test.result_json = "#{test.id}.json" if test.option[:json] && test.option[:json] != "FALSE"
      test
    end
  end

  # Create files referenced in the manifest
  def create_files
    tests.each do |test|
      FileUtils.mkdir(test.id.to_s) unless Dir.exist?(test.id.to_s) if test.option[:dir]
      files = []
      files << test.action
      files << test.result_rdfa  if test.result_rdfa
      files << test.result_json if test.result_json
      files.compact.select {|f| !File.exist?(f)}.each do |f|
        File.open(f, "w") {|io| io.puts( f.end_with?('.json') ? "{}" : "")}
      end
    end
  end

  def test_class(test, variant)
    case variant
    when :rdfa
      case test.option[:rdfa]
      when "FALSE" then "csvt:NegativeRdfaTest"
      when "TRUE" then "csvt:ToRdfaTest"
      else
        raise "unknown combination of '#{variant}' with #{test}"
      end
    when :json
      case test.option[:json]
      when "FALSE" then "csvt:NegativeJsonTest"
      when "TRUE" then "csvt:ToJsonTest"
      else
        raise "unknown combination of '#{variant}' with #{test}"
      end
    end
  end

  def to_jsonld(variant)
    context = ::JSON.parse %({
      "xsd": "http://www.w3.org/2001/XMLSchema#",
      "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
      "mf": "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#",
      "mq": "http://www.w3.org/2001/sw/DataAccess/tests/test-query#",
      "rdft": "http://www.w3.org/ns/rdftest#",
      "mdt": "https://w3c.github.io/microdata/tests/vocab#",
      "id": "@id",
      "type": "@type",
      "action": {"@id": "mf:action",  "@type": "@id"},
      "approval": {"@id": "rdft:approval", "@type": "@id"},
      "comment": "rdfs:comment",
      "contentType": "csvt:contentType",
      "entries": {"@id": "mf:entries", "@type": "@id", "@container": "@list"},
      "label": "rdfs:label",
      "name": "mf:name",
      "option": "csvt:option",
      "result": {"@id": "mf:result", "@type": "@id"}
    })

    manifest = {
      "@context" => context,
      "id" => "manifest-#{variant}",
      "type" => "mf:Manifest",
      "label" => TITLE[variant],
      "comment" => DESCRIPTION[variant],
      "entries" => []
    }

    tests.each do |test|
      next unless test.option[variant]

      entry = {
        "id" => "manifest-#{variant}##{test.id}",
        "type" => test_class(test, variant),
        "name" => test.name,
        "comment" => test.comment,
        "approval" => (test.approval ? "rdft:#{test.approval}" : "rdft:Proposed"),
        "action" => test.action,
      }

      entry["result"] = test.result_rdfa if test.result_rdfa && variant == :rdfa
      entry["result"] = test.result_json if test.result_json && variant == :json

      manifest["entries"] << entry
    end

    manifest.to_json(JSON_STATE)
  end

  def to_html
    # Create vocab.html using vocab_template.haml and compacted vocabulary
    template = File.read("template.haml")
    manifests = %w(json rdfa).inject({}) do |memo, v|
      memo["manifest-#{v}"] = ::JSON.load(File.read("manifest-#{v}.jsonld"))
      memo
    end

    Haml::Engine.new(template, :format => :html5).render(self,
      man: ::JSON.load(File.read("manifest.jsonld")),
      manifests: manifests
    )
  end

  def to_ttl(variant)
    output = []
    output << %(## Microdata tests
## Distributed under both the W3C Test Suite License[1] and the W3C 3-
## clause BSD License[2]. To contribute to a W3C Test Suite, see the
## policies and contribution forms [3]
##
## 1. http://www.w3.org/Consortium/Legal/2008/04-testsuite-license
## 2. http://www.w3.org/Consortium/Legal/2008/03-bsd-license
## 3. http://www.w3.org/2004/10/27-testcases

@prefix : <manifest-#{variant}#> .
@prefix rdf:  <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix mf:   <http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#> .
@prefix mdt:  <https://w3c.github.io/microdata/tests/vocab#> .
@prefix rdft: <http://www.w3.org/ns/rdftest#> .

<manifest-#{variant}>  a mf:Manifest ;
)
    output << %(  rdfs:label "#{TITLE[variant]}";)
    output << %(  rdfs:comment """#{DESCRIPTION[variant]}""";)
    output << %(  mf:entries \()

    tests.select do |t|
      case variant
      when :nonnorm then t.option[:nonnorm]
      else t.option[variant] && !t.option[:nonnorm]
      end
    end.map {|t| ":#{t.id}"}.each_slice(10) do |entries|
      output << %(    #{entries.join(' ')})
    end
    output << %(  \) .)

    tests.select do |t|
      case variant
      when :nonnorm then t.option[:nonnorm]
      else t.option[variant] && !t.option[:nonnorm]
      end
    end.each do |test|
      output << "" # separator
      output << ":#{test.id} a #{test_class(test, variant)};"
      output << %(  mf:name "#{test.name}";)
      output << %(  rdfs:comment """#{test.comment}""";)
      output << %(  rdft:approval #{(test.approval ? "rdft:#{test.approval}" : "rdft:Proposed")};)
      output << %(  mf:action <#{test.action}>;)
      output << %(  mf:result <#{test.result_rdfa}>;) if test.result_rdfa && variant == :rdf
      output << %(  mf:result <#{test.result_json}>;) if test.result_json && [:json, :nonnorm].include?(variant)
      output << %(  .)
    end
    output.join("\n")
  end
end

options = {
  output: $stdout
}

OPT_ARGS = [
  ["--format", "-f",  GetoptLong::REQUIRED_ARGUMENT,"Output format, default #{options[:format].inspect}"],
  ["--output", "-o",  GetoptLong::REQUIRED_ARGUMENT,"Output to the specified file path"],
  ["--quiet",         GetoptLong::NO_ARGUMENT,      "Supress most output other than progress indicators"],
  ["--touch",         GetoptLong::NO_ARGUMENT,      "Create referenced files and directories if missing"],
  ["--variant",       GetoptLong::REQUIRED_ARGUMENT,"Test variant, 'rdfa', 'json'"],
  ["--help", "-?",    GetoptLong::NO_ARGUMENT,      "This message"]
]
def usage
  STDERR.puts %{Usage: #{$0} [options] URL ...}
  width = OPT_ARGS.map do |o|
    l = o.first.length
    l += o[1].length + 2 if o[1].is_a?(String)
    l
  end.max
  OPT_ARGS.each do |o|
    s = "  %-*s  " % [width, (o[1].is_a?(String) ? "#{o[0,2].join(', ')}" : o[0])]
    s += o.last
    STDERR.puts s
  end
  exit(1)
end

opts = GetoptLong.new(*OPT_ARGS.map {|o| o[0..-2]})

opts.each do |opt, arg|
  case opt
  when '--format'       then options[:format] = arg.to_sym
  when '--output'       then options[:output] = File.open(arg, "w")
  when '--quiet'        then options[:quiet] = true
  when '--touch'        then options[:touch] = true
  when '--variant'      then options[:variant] = arg.to_sym
  when '--help'         then usage
  end
end

vocab = Manifest.new
vocab.create_files if options[:touch]
if options[:format] || options[:variant]
  case options[:format]
  when :jsonld  then options[:output].puts(vocab.to_jsonld(options[:variant]))
  when :ttl     then options[:output].puts(vocab.to_ttl(options[:variant]))
  when :html    then options[:output].puts(vocab.to_html)
  else  STDERR.puts "Unknown format #{options[:format].inspect}"
  end
else
  %w(json rdfa).each do |variant|
    %w(jsonld).each do |format|
      File.open("manifest-#{variant}.#{format}", "w") do |output|
        output.puts(vocab.send("to_#{format}".to_sym, variant.to_sym))
      end
    end
  end
  File.open("index.html", "w") do |output|
    output.puts(vocab.to_html)
  end
end
