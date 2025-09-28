# frozen_string_literal: true

require "test_helper"

class HelpControllerTest < ActionDispatch::IntegrationTest
  test "should get show" do
    get help_path

    assert_response(:success)
  end

  test "renders help page content" do
    get help_path

    assert_response(:success)
    assert_select "h1", text: I18n.t("ui.help.header")
    assert_select "p", text: I18n.t("ui.help.subheader")
  end

  test "renders primary help sections" do
    get help_path

    assert_response(:success)
    assert_select "h2", text: I18n.t("ui.help.how_it_works")
    assert_select "h2", text: "Auto-sync Features"
    assert_select "h2", text: "Finding Your Apple Calendar"
    assert_select "h2", text: "Authentication Setup"
  end

  test "renders secondary help sections" do
    get help_path

    assert_response(:success)
    assert_select "h2", text: "Status Indicators"
    assert_select "h2", text: "Troubleshooting"
    assert_select "h2", text: "Best Practices"
  end

  test "renders ordered list for how it works" do
    get help_path

    assert_response(:success)
    assert_select "ol li", text: I18n.t("ui.help.add_source")
    assert_select "ol li", text: I18n.t("ui.help.choose_destination")
    assert_select "ol li", text: I18n.t("ui.help.enable_auto_sync")
    assert_select "ol li", text: I18n.t("ui.help.click_sync")
    assert_select "ol li", text: I18n.t("ui.help.review_events")
  end

  test "renders tip section" do
    get help_path

    assert_response(:success)
    assert_select "p", text: I18n.t("ui.help.tip")
  end

  test "includes shared top navigation" do
    get help_path

    assert_response(:success)
    assert_select "nav.flex.items-center"
    assert_select "nav a[href='#{help_path}']"
  end

  test "renders with correct layout" do
    get help_path

    assert_response(:success)
    assert_select "div.min-h-screen.bg-slate-950.text-slate-100"
    assert_select "header.bg-slate-900\\/70.backdrop-blur.sticky.top-0"
  end

  test "uses help route" do
    assert_routing({ path: "/help", method: :get }, { controller: "help", action: "show" })
  end

  test "renders status indicator examples" do
    get help_path

    assert_response(:success)
    assert_select "span", text: "Active"
    assert_select "span", text: "Paused"
    assert_select "span", text: "Auto-sync"
    assert_select "span", text: "Auto-sync disabled"
  end

  test "renders troubleshooting sections" do
    get help_path

    assert_response(:success)
    assert_select "h3", text: "Events Not Appearing"
    assert_select "h3", text: "Auto-sync Not Working"
    assert_select "h3", text: "Authentication Issues"
  end

  test "renders best practices sections" do
    get help_path

    assert_response(:success)
    assert_select "h3", text: "Auto-sync Configuration"
    assert_select "h3", text: "Event Mappings"
    assert_select "h3", text: "Performance"
  end
end
