# frozen_string_literal: true

module MarkdownHelper
  def render_markdown(text)
    return if text.blank?

    html = Commonmarker.to_html(text, options: {
                                  render: { unsafe: false, hardbreaks: true },
                                  extension: { header_ids: nil, table: false, tasklist: false, shortcodes: false }
                                }, plugins: { syntax_highlighter: nil })
    tag.div(sanitize(html, tags: %w[p br strong em del a ul ol li blockquote pre code h1 h2 h3 h4 h5 h6 hr],
                           attributes: %w[href title start]), class: 'markdown-content')
  end
end
