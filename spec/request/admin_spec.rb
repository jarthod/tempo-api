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
      stub_const("EDF::DEFAULT_TEMPO_API", :couleur)
      page.driver.browser.basic_authorize 'admin', 'test'
   end

    it "display current colors" do
      VCR.use_cassette("/admin") do
        visit '/admin'
      end
      expect(page.status_code).to eq(200)
      expect(page).to have_content('TEMPO: ● Blanc / ● Blanc')
      expect(page).to have_content('EJP: ● Vert / ● Rouge')
    end

    it "display devices and can change mode" do
      d = Device.create!(id: 255)
      VCR.use_cassette("/admin") do
        visit '/admin'
        expect(page).to have_content('FF TEMPO ⇄')
        expect {
          click_on('⇄')
        }.to change { d.reload.mode }.from('tempo').to('ejp')
        expect(page).to have_content('FF EJP ⇄')
        expect {
          click_on('⇄')
        }.to change { d.reload.mode }.from('ejp').to('tempo')
        expect(page).to have_content('FF TEMPO ⇄')
      end
    end
  end
end
