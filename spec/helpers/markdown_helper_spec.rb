# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MarkdownHelper, :aggregate_failures, type: :helper do
  def rendered(text)
    Nokogiri::HTML.fragment(helper.render_markdown(text).to_s)
  end

  it 'renders headings, emphasis, lists, and ordinary links' do
    html = rendered("## Arrival\n\n**Bring** *supplies*.\n\n- Pencils\n- [Directions](https://example.test/visit)")
    expect(html.at_css('h2').text).to eq('Arrival')
    expect(html.at_css('strong').text).to eq('Bring')
    expect(html.at_css('em').text).to eq('supplies')
    expect(html.css('ul li').map(&:text)).to eq(%w[Pencils Directions])
    expect(html.at_css('a')['href']).to eq('https://example.test/visit')
  end

  it 'preserves plain paragraphs, line breaks, and code without interpreting code as HTML' do
    html = rendered("First line\nSecond line\n\nAnother paragraph.\n\n```\n<script>alert(1)</script>\n```")
    expect(html.css('p').length).to eq(2)
    expect(html.at_css('br')).to be_present
    expect(html.at_css('pre code').text).to include('<script>alert(1)</script>')
    expect(html.at_css('script')).to be_nil
  end

  it 'removes executable HTML, unsafe links, and embedded images' do
    html = rendered(<<~MARKDOWN)
      <script>alert(1)</script>

      <iframe src="https://example.test/embed"></iframe>

      [Unsafe](javascript:alert%281%29) [Data](data:text/html,test)
      ![Remote Image](https://example.test/track.png)
      <img src=x onerror=alert(1)> <a href="javascript:alert(1)" onclick="alert(1)">Raw</a>
    MARKDOWN
    expect(html.css('script, iframe, img, [onclick], [onerror]')).to be_empty
    expect(html.css('a').filter_map { |link| link['href'].presence }).to be_empty
  end

  it 'omits empty content instead of creating empty sections' do
    expect(helper.render_markdown(nil)).to be_nil
    expect(helper.render_markdown(" \n")).to be_nil
  end
end
