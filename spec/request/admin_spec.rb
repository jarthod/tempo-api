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

    it "display current colors" do
      VCR.use_cassette("/admin") do
        visit '/admin'
      end
      expect(page.status_code).to eq(200)
      expect(page).to have_content('API 1: ● Blanc / ● Blanc (api-couleur-tempo.fr)')
      expect(page).to have_content('API 2: ● Inconnu / ● Inconnu (services-rte.com)') # does not support looking back in time
      expect(page).to have_content('EJP: ● Vert / ● Rouge')
      expect(page).to have_content('ZEN FLEX: ● Blanc / ● Blanc')
    end

    it "display devices and can change mode via select" do
      d = Device.create!(id: 255)
      VCR.use_cassette("/admin") do
        visit '/admin'
        expect(page).to have_content('0000000000FF')
        expect(page).to have_select('mode', selected: 'TEMPO')
        expect {
          select 'EJP', from: 'mode'
          find('button[type=submit]', visible: :all).click
        }.to change { d.reload.mode }.from('tempo').to('ejp')
        expect(page).to have_select('mode', selected: 'EJP')
        expect {
          select 'ZEN_FLEX', from: 'mode'
          find('button[type=submit]', visible: :all).click
        }.to change { d.reload.mode }.from('ejp').to('zen_flex')
        expect(page).to have_select('mode', selected: 'ZEN_FLEX')
        expect {
          select 'TEMPO', from: 'mode'
          find('button[type=submit]', visible: :all).click
        }.to change { d.reload.mode }.from('zen_flex').to('tempo')
        expect(page).to have_select('mode', selected: 'TEMPO')
      end
    end
  end
end
