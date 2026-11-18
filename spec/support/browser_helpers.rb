# frozen_string_literal: true

require 'capybara/rspec'
# Keep a short navigation grace; waiting matchers synchronize browser results.
ENV['FERRUM_CLICK_WAIT'] ||= '0.01'
require 'capybara/cuprite'

Capybara.register_driver(:posebook_chrome) do |app|
  # GitHub-hosted Ubuntu runners restrict Chrome's user-namespace sandbox; local runs keep it.
  options = ENV['CI'] ? { 'no-sandbox' => nil } : {}
  Capybara::Cuprite::Driver.new(app, window_size: BrowserHelpers::VIEWPORTS.fetch(:desktop), timeout: 20,
                                     process_timeout: 30, browser_options: options)
end
Capybara.server = :puma, { Silent: true }
Capybara.default_max_wait_time = 5
Capybara.disable_animation = true

module BrowserHelpers
  VIEWPORTS = { desktop: [1280, 900], phone: [390, 844], narrow: [320, 640] }.freeze

  def sign_in_through_browser(user)
    visit new_session_path
    fill_in 'Email', with: user.email
    fill_in 'Password', with: DatabaseHelpers::TEST_PASSWORD
    click_on 'Sign In'
    expect(page).to have_link(user.name)
  end

  def sign_out_through_browser
    click_on 'Sign Out'
    expect(page).to have_current_path(new_session_path)
    expect(page).to have_button('Sign In')
  end

  def resize_to(viewport)
    page.current_window.resize_to(*VIEWPORTS.fetch(viewport))
  end

  def each_viewport(&)
    VIEWPORTS.each_key do |viewport|
      resize_to(viewport)
      yield viewport
    end
  ensure
    resize_to(:desktop)
  end

  # rubocop:disable Spellcheck/Spelling -- JavaScript and Chrome DevTools Protocol identifiers.
  def expect_no_horizontal_overflow
    width = page.evaluate_script('document.documentElement.scrollWidth')
    viewport = page.evaluate_script('window.innerWidth')
    expect(width).to be <= viewport, "#{page.current_path} is #{width} pixels wide in a #{viewport}-pixel viewport"
  end

  def without_javascript
    page.driver.browser.page.command('Emulation.setScriptExecutionDisabled', value: true)
    yield
  ensure
    page.driver.browser.page.command('Emulation.setScriptExecutionDisabled', value: false)
  end

  # Replaces navigator.clipboard in the current page only; the host clipboard is never touched.
  def stub_clipboard(failure: false)
    page.execute_script(<<~JAVASCRIPT, failure)
      const failure = arguments[0];
      window.copiedText = null;
      Object.defineProperty(navigator, 'clipboard', { configurable: true, value: {
        writeText: async text => { if (failure) throw new Error('Blocked'); window.copiedText = text; }
      } });
    JAVASCRIPT
  end

  def copied_text
    page.evaluate_script('window.copiedText')
  end

  def mark_page
    page.execute_script('window.unchangedPage = true')
  end

  def expect_unchanged_page
    expect(page.evaluate_script('window.unchangedPage')).to be(true)
  end

  def top_of(element)
    element.evaluate_script('this.getBoundingClientRect().top')
  end

  def width_of(element)
    element.evaluate_script('this.getBoundingClientRect().width')
  end

  # Drags copies of one file under the given names onto the photo upload form; returns whether it was highlighted.
  def drop_files(path, names)
    page.execute_script(<<~JAVASCRIPT, Base64.strict_encode64(File.binread(path)), names)
      const bytes = Uint8Array.from(atob(arguments[0]), character => character.charCodeAt(0));
      const transfer = new DataTransfer();
      arguments[1].forEach(name =>
        transfer.items.add(new File([bytes], name, { type: name.endsWith(".png") ? "image/png" : "text/plain" })));
      const form = document.querySelector("form[data-photo-action] input[type='file']").form;
      form.dispatchEvent(new DragEvent("dragover", { bubbles: true, cancelable: true, dataTransfer: transfer }));
      window.dropTarget = form.classList.contains("photo-drop-target");
      form.dispatchEvent(new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer: transfer }));
    JAVASCRIPT
    page.evaluate_script('window.dropTarget')
  end
  # rubocop:enable Spellcheck/Spelling

  # Writes a full-page PNG only when BROWSER_SCREENSHOTS names a directory, for attaching to PRs.
  def capture_screenshot(name)
    directory = ENV.fetch('BROWSER_SCREENSHOTS', nil)
    return if directory.blank?

    FileUtils.mkdir_p(directory)
    page.save_screenshot(File.join(directory, "#{name}.png"), full: true) # rubocop:disable Lint/Debugger -- opt-in PR capture.
  end
end

RSpec.configure do |config|
  config.include BrowserHelpers, type: :system
  config.before(:each, type: :system) { driven_by(:posebook_chrome) }
end
