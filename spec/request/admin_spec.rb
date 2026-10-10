require 'app_helper'

RSpec.describe '/admin', :request do
  before do
    travel_to Time.new(2025, 2, 11, 16, 0, 0, "+01:00")
  end

  it "requires Basic Auth" do
    visit '/admin'
    expect(page.status_code).to eq(401)
  end

  context "with password" do
    before do
      page.driver.browser.basic_authorize 'admin', 'test'
   end

    it "display current colors with inline manual override selects" do
      VCR.use_cassette("/admin") do
        visit '/admin'
      end
      expect(page.status_code).to eq(200)
      expect(page).to have_content('API 1: ● Blanc / ● Blanc (api-couleur-tempo.fr)')
      expect(page).to have_content('API 2: ● Inconnu / ● Inconnu (services-rte.com)') # does not support looking back in time
      expect(page).to have_content('EJP: ● Vert / ● Rouge')
      expect(page).to have_content('ZEN FLEX: ● Eco / ● Eco')
    end

    it "display devices with their mode, settings and a link to their config page" do
      Device.create!(id: 255)
      Device.create!(id: 95235612490712, mode: 'hphc', hc_ranges: [["22:00", "06:00"], ["12:00", "14:00"]])
      VCR.use_cassette("/admin") do
        visit '/admin'
      end
      expect(page).to have_content('0000000000FF TEMPO')
      expect(page).to have_content('569DC4DA3BD8 HP / HC (HC 22:00–06:00, 12:00–14:00)')
      expect(page).to have_link('569DC4DA3BD8', href: '/id/569dc4da3bd8')
    end

    it "allows setting and clearing manual overrides inline" do
      VCR.use_cassette("/admin") do
        visit '/admin'

        today_date = Date.new(2025, 2, 11)

        zen_today_form = all("form[action='/admin/manual_override']").find do |form|
          form.has_field?('contract', with: 'zen_flex', type: :hidden) &&
          form.has_field?('target', with: 'today', type: :hidden)
        end

        # Initial page load already fills the cache via API (ECO); override to Rouge
        expect {
          within(zen_today_form) do
            select 'Rouge', from: 'color'
            find('button[type=submit]', visible: :all).click
          end
        }.to change { $cache.read("zen_flex_color/#{today_date}") }.from(ECO).to(RED)

        expect(page).to have_content('ZEN FLEX: ● Rouge / ● Eco')

        # Reset to Auto: clears the override then the page re-fetches from API (ECO via VCR)
        zen_today_form = all("form[action='/admin/manual_override']").find do |form|
          form.has_field?('contract', with: 'zen_flex', type: :hidden) &&
          form.has_field?('target', with: 'today', type: :hidden)
        end

        expect {
          within(zen_today_form) do
            select 'Auto', from: 'color'
            find('button[type=submit]', visible: :all).click
          end
        }.to change { $cache.read("zen_flex_color/#{today_date}") }.from(RED).to(ECO)

        expect(page).to have_content('ZEN FLEX: ● Eco / ● Eco')
      end
    end
  end
end
