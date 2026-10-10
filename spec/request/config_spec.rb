require 'app_helper'

RSpec.describe '/id', :request do
  it "asks for the device ID and redirects to its bookmarkable config page" do
    visit '/id'
    expect(page).to have_content("l'identifiant du Temp'Orb à configurer")
    expect(page).not_to have_css('meta[name=robots]', visible: false)
    fill_in 'id', with: '569DC4DA3BD8'
    click_on 'Valider'
    expect(page).to have_current_path('/id/569dc4da3bd8')
    expect(page.status_code).to eq(404)
    expect(page).to have_content("Aucun Temp'Orb trouvé avec l'identifiant « 569dc4da3bd8 »")
  end

  it "is not indexed once an ID is given" do
    Device.create!(id: 95235612490712)
    visit '/id/569dc4da3bd8'
    expect(page).to have_css('meta[name=robots][content="noindex, nofollow"]', visible: false)
  end

  context "on config.temporb.fr" do
    before { Capybara.app_host = 'http://config.temporb.fr' }
    after { Capybara.app_host = nil }

    it "serves the ID form on /" do
      device = Device.create!(id: 95235612490712)
      visit '/'
      fill_in 'id', with: '569dc4da3bd8'
      click_on 'Valider'
      expect(page).to have_current_path('/id/569dc4da3bd8')
      expect(page).to have_css('.contract-option[aria-pressed=true]', text: 'Tempo')
      find('#contract', visible: false).set('ejp') # no JS driver
      click_on 'Enregistrer les paramètres'
      expect(device.reload.mode).to eq('ejp')
      expect(page).to have_current_path('/id/569dc4da3bd8')
      expect(page).to have_css('.flash.notice', text: "Paramètres enregistrés")
    end
  end

  context "with a known device" do
    let!(:device) { Device.create!(id: 95235612490712, mode: 'tempo', settings: { 'other' => 1 }) }

    it "changes the contract and flashes a success message once" do
      visit '/id/569dc4da3bd8'
      expect(page).to have_css('.contract-option[aria-pressed=true]', text: 'Tempo')
      expect(page).to have_field('hc_night_start', disabled: true, visible: false)
      find('#contract', visible: false).set('ejp') # no JS driver
      click_on 'Enregistrer les paramètres'
      expect(device.reload.mode).to eq('ejp')
      expect(page).to have_current_path('/id/569dc4da3bd8')
      expect(page).to have_css('.flash.notice', text: "Paramètres enregistrés")
      expect(page).to have_content("jusqu'à 2 heures")
      expect(page).to have_content("débrancher puis le rebrancher")

      visit '/id/569dc4da3bd8'
      expect(page).not_to have_content("Paramètres enregistrés")
    end

    it "saves HP/HC off-peak ranges in settings" do
      page.driver.submit :patch, '/id/569dc4da3bd8', mode: 'hphc', hc_night_start: '22:30', hc_night_end: '06:30',
        hc_day_enabled: '1', hc_day_start: '12:00', hc_day_end: '14:00'
      expect(device.reload.mode).to eq('hphc')
      expect(device.settings).to eq('other' => 1, 'hc_ranges' => [['22:30', '06:30'], ['12:00', '14:00']])

      expect(page).to have_current_path('/id/569dc4da3bd8')
      expect(page).to have_css('.contract-option[aria-pressed=true]', text: 'HP / HC')
      expect(page).to have_field('hc_night_start', with: '22:30')
      expect(page).to have_field('hc_day_end', with: '14:00')
      expect(page).to have_checked_field('hc_day_enabled')
    end

    it "ignores daytime range when unchecked" do
      page.driver.submit :patch, '/id/569dc4da3bd8', mode: 'hphc', hc_night_start: '22:30', hc_night_end: '06:30',
        hc_day_start: '12:00', hc_day_end: '14:00'
      expect(device.reload.hc_ranges).to eq([['22:30', '06:30']])
    end

    it "shows an error for invalid HP/HC ranges" do
      page.driver.submit :patch, '/id/569dc4da3bd8', mode: 'hphc', hc_night_start: '22:00', hc_night_end: '22:00'
      expect(page.status_code).to eq(422)
      expect(page).to have_css('.flash.alert', text: "Les heures de début et de fin doivent être différentes")
      expect(device.reload.mode).to eq('tempo')
    end

    it "shows an error for unknown contract" do
      page.driver.submit :patch, '/id/569dc4da3bd8', mode: 'foo'
      expect(page.status_code).to eq(422)
      expect(page).to have_css('.flash.alert', text: "Veuillez sélectionner un contrat.")
    end
  end
end
