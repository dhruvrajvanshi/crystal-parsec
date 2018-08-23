require "spec"
require "../src/parsec.cr"
include Parsec

describe Parser do
  it "parses using Parser.of" do 
    Parser.of(42).parse("asdf").should eq 42
  end

  it "fails with correct error on Parsec::fail" do
    result = fail(Int32, "Failure").parse("asdf")
    result.class.should eq ParseError
    result.as(ParseError).message.should eq "Failure"
  end

  it "Parsec::char" do
    char('c').parse("c").should eq 'c'
    char('c').parse("a").class.should eq ParseError
  end

  it "Parsec::string" do
    string("asdf").parse("asdf").should eq "asdf"
    string("asdf").parse("asd").class.should eq ParseError
  end

  it "Parsec::one_of" do
    p = one_of("123")
    p.parse("a").class.should eq ParseError
    p.parse("1").should eq '1'
    p.parse("2").should eq '2'
    p.parse("3").should eq '3'
  end

  it "Parsec::none_of" do
    p = none_of "1234"
    p.parse("a").should eq 'a'
    p.parse("1").class.should eq ParseError
    p.parse("2").class.should eq ParseError
    p.parse("3").class.should eq ParseError
  end

  it "Parsec::many" do
    p = many (char 'c')
    p.parse("").should eq [] of Char
    p.parse("c").should eq ['c']
    p.parse("ccc").should eq ['c', 'c', 'c']
  end

  it "Parsec::one_or_more" do
    p = one_or_more (char 'c')
    p.parse("").class.should eq ParseError
    p.parse("c").should eq ['c']
    p.parse("cc").should eq ['c', 'c']
  end

  it "Parsec::sep_by" do
    p = sep_by (char 'c'), (char ',')
    p.parse("").should eq [] of Char
    p.parse("c").should eq ['c']
    p.parse("c,c").should eq ['c', 'c']
    p.parse("c,c,c").should eq ['c', 'c', 'c']
    p.parse("c,asdf").should eq ['c']
  end

  it "Parser#bind" do
    p = Parser.of(1).bind do |x| 
      Parser.of(x+1) 
    end
    p.parse("").should eq 2

    p = char('c').bind {|c| Parser.of(c.to_s)}
    p.parse("c").should eq "c"
  end

  it "Parser#map" do
    p = Parser.of(2).map {|x| x + 1}
    p.parse("").should eq 3
  end

  it "Parser#pass_through" do
    px = one_or_more(digit)
      .pass_through(string "px")
      .map {|x| x.join() }
      .map {|x| x.to_i }
    px.parse("10px").should eq 10
    px.parse("10").class.should eq ParseError
  end
end