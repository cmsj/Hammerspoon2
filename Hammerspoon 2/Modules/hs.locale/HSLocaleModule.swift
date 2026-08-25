//
//  HSLocaleModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

// MARK: - File-scope helpers (locale detail extraction)

private func localeMeasurementSystem(_ system: Locale.MeasurementSystem) -> String {
    switch system {
    case .metric: return "metric"
    case .us: return "us"
    case .uk: return "uk"
    default: return "metric"
    }
}

private func localeTemperatureUnit(_ locale: Locale) -> String? {
    let key = NSLocale.Key(rawValue: "kCFLocaleTemperatureUnitKey")
    return (locale as NSLocale).object(forKey: key) as? String
}

private func localeCalendarDetails(_ locale: Locale) -> [String: Any] {
    var calendar = Calendar(identifier: locale.calendar.identifier)
    calendar.locale = locale
    let nsCalendar = calendar as NSCalendar

    return [
        "identifier": nsCalendar.calendarIdentifier.rawValue,
        "firstWeekday": nsCalendar.firstWeekday,
        "minimumDaysInFirstWeek": nsCalendar.minimumDaysInFirstWeek,
        "amSymbol": nsCalendar.amSymbol,
        "pmSymbol": nsCalendar.pmSymbol,
        "eraSymbols": nsCalendar.eraSymbols,
        "longEraSymbols": nsCalendar.longEraSymbols,
        "monthSymbols": nsCalendar.monthSymbols,
        "shortMonthSymbols": nsCalendar.shortMonthSymbols,
        "standaloneMonthSymbols": nsCalendar.standaloneMonthSymbols,
        "shortStandaloneMonthSymbols": nsCalendar.shortStandaloneMonthSymbols,
        "veryShortMonthSymbols": nsCalendar.veryShortMonthSymbols,
        "veryShortStandaloneMonthSymbols": nsCalendar.veryShortStandaloneMonthSymbols,
        "quarterSymbols": nsCalendar.quarterSymbols,
        "shortQuarterSymbols": nsCalendar.shortQuarterSymbols,
        "standaloneQuarterSymbols": nsCalendar.standaloneQuarterSymbols,
        "shortStandaloneQuarterSymbols": nsCalendar.shortStandaloneQuarterSymbols,
        "weekdaySymbols": nsCalendar.weekdaySymbols,
        "shortWeekdaySymbols": nsCalendar.shortWeekdaySymbols,
        "standaloneWeekdaySymbols": nsCalendar.standaloneWeekdaySymbols,
        "shortStandaloneWeekdaySymbols": nsCalendar.shortStandaloneWeekdaySymbols,
        "veryShortWeekdaySymbols": nsCalendar.veryShortWeekdaySymbols,
        "veryShortStandaloneWeekdaySymbols": nsCalendar.veryShortStandaloneWeekdaySymbols
    ]
}

private func localeDetails(_ locale: Locale) -> [String: Any] {
    var result: [String: Any] = [
        "identifier": locale.identifier,
        "measurementSystem": localeMeasurementSystem(locale.measurementSystem),
        "usesMetricSystem": locale.measurementSystem == .metric,
        "collationIdentifier": locale.collation.identifier,
        "calendar": localeCalendarDetails(locale),
        "timeFormatIs24Hour": locale.hourCycle == .zeroToTwentyThree || locale.hourCycle == .oneToTwentyFour
    ]

    if let languageCode = locale.language.languageCode?.identifier { result["languageCode"] = languageCode }
    if let countryCode = locale.region?.identifier { result["countryCode"] = countryCode }
    if let scriptCode = locale.language.script?.identifier { result["scriptCode"] = scriptCode }
    if let variantCode = locale.variant?.identifier { result["variantCode"] = variantCode }
    if let currencyCode = locale.currency?.identifier { result["currencyCode"] = currencyCode }
    if let currencySymbol = locale.currencySymbol { result["currencySymbol"] = currencySymbol }
    if let decimalSeparator = locale.decimalSeparator { result["decimalSeparator"] = decimalSeparator }
    if let groupingSeparator = locale.groupingSeparator { result["groupingSeparator"] = groupingSeparator }
    if let quotationBegin = locale.quotationBeginDelimiter { result["quotationBeginDelimiter"] = quotationBegin }
    if let quotationEnd = locale.quotationEndDelimiter { result["quotationEndDelimiter"] = quotationEnd }
    if let altQuotationBegin = locale.alternateQuotationBeginDelimiter {
        result["alternateQuotationBeginDelimiter"] = altQuotationBegin
    }
    if let altQuotationEnd = locale.alternateQuotationEndDelimiter {
        result["alternateQuotationEndDelimiter"] = altQuotationEnd
    }
    if let temperatureUnit = localeTemperatureUnit(locale) { result["temperatureUnit"] = temperatureUnit }

    return result
}

// MARK: - Module API protocol

/// Retrieve information about the user's Language & Region settings, and respond to changes.
///
/// Locales encapsulate linguistic, cultural, and technological conventions — things like the
/// symbol used for a decimal separator, or the way dates and calendars are formatted.
///
/// ## Reading locale information
///
/// ```js
/// console.log("Current locale: " + hs.locale.current())
/// const info = hs.locale.details()
/// console.log("Uses metric: " + info.usesMetricSystem)
/// ```
///
/// ## Watching for changes
///
/// ```js
/// hs.locale.addWatcher(() => {
///     console.log("Locale settings changed: " + JSON.stringify(hs.locale.details()))
/// })
/// ```
@objc protocol HSLocaleModuleAPI: JSExport {

    /// Returns the identifiers for all locales available on the system.
    ///
    /// - Returns: An array of locale identifier strings (e.g. `["en_US", "de_CH", "ja_JP"]`).
    /// - Example:
    /// ```js
    /// hs.locale.availableLocales().forEach(id => console.log(id))
    /// ```
    func availableLocales() -> [String]

    /// Returns the user's currently selected locale identifier.
    ///
    /// - Returns: The identifier of the user's currently selected locale (e.g. `"en_US"`).
    /// - Example:
    /// ```js
    /// console.log("Current locale: " + hs.locale.current())
    /// ```
    func current() -> String

    /// Returns the user's preferred languages, in priority order.
    ///
    /// - Returns: An array of language identifier strings, most preferred first.
    /// - Example:
    /// ```js
    /// hs.locale.preferredLanguages().forEach(l => console.log(l))
    /// ```
    func preferredLanguages() -> [String]

    /// Returns detailed information about the current or a specified locale.
    ///
    /// - Parameter identifier?: A locale identifier from `availableLocales()`. If omitted, the
    ///   user's currently selected locale is used.
    /// - Returns: A dictionary describing the locale, including (where available):
    ///   `identifier`, `languageCode`, `countryCode`, `scriptCode`, `variantCode`,
    ///   `currencyCode`, `currencySymbol`, `decimalSeparator`, `groupingSeparator`,
    ///   `collationIdentifier`, `measurementSystem` (`"metric"`, `"us"`, or `"uk"`),
    ///   `usesMetricSystem`, `temperatureUnit`, `timeFormatIs24Hour`,
    ///   `quotationBeginDelimiter`, `quotationEndDelimiter`,
    ///   `alternateQuotationBeginDelimiter`, `alternateQuotationEndDelimiter`,
    ///    and `calendar` — a nested object describing the locale's
    ///   calendar (`identifier`, `firstWeekday`, `minimumDaysInFirstWeek`, `amSymbol`,
    ///   `pmSymbol`, and arrays of era/month/quarter/weekday symbols in their standard,
    ///   short, standalone, and very-short forms).
    /// - Example:
    /// ```js
    /// const info = hs.locale.details("de_CH")
    /// console.log(info.currencySymbol + " " + info.decimalSeparator)
    /// console.log(info.calendar.monthSymbols.join(", "))
    /// ```
    func details(_ identifier: String?) -> [String: Any]

    /// Returns the localized display name for a locale identifier.
    ///
    /// - Parameter localeCode: The locale identifier to look up (e.g. `"de_CH"`). Must be one
    ///   of the strings returned by `availableLocales()`.
    /// - Parameter baseLocaleCode?: The locale to display the name in. If omitted, the user's
    ///   currently selected locale is used. Must be one of the strings returned by
    ///   `availableLocales()`.
    /// - Returns: A dictionary with `name` (e.g. `"German"`) and `nameWithDialect`
    ///   (e.g. `"German (Switzerland)"`), or `null` if either locale code is invalid.
    /// - Example:
    /// ```js
    /// const name = hs.locale.localizedName("de_CH")
    /// console.log(name.name + " / " + name.nameWithDialect)
    /// ```
    func localizedName(_ localeCode: String, _ baseLocaleCode: String?) -> [String: String]?

    // MARK: Watcher (Pattern A)

    /// Registers a listener that fires whenever any of the user's locale settings change.
    ///
    /// The listener is called with no arguments. Read `current()` or `details()` inside the
    /// callback to inspect the new state.
    ///
    /// The OS subscription starts lazily on the first listener and is released automatically
    /// when the last listener is removed via `removeWatcher`.
    /// - Parameter listener: {() => void} A function called when locale settings change.
    /// - Example:
    /// ```js
    /// hs.locale.addWatcher(() => {
    ///     console.log("Locale changed to: " + hs.locale.current())
    /// })
    /// ```
    func addWatcher(_ listener: JSFunction)

    /// Removes a previously registered locale change listener.
    ///
    /// - Parameter listener: The function originally passed to `addWatcher`.
    /// - Example:
    /// ```js
    /// const handler = () => console.log("changed")
    /// hs.locale.addWatcher(handler)
    /// hs.locale.removeWatcher(handler)
    /// ```
    func removeWatcher(_ listener: JSFunction)

    /// SKIP_DOCS
    @objc(_addWatcher:) func _addWatcher(_ callback: JSFunction)
    /// SKIP_DOCS
    @objc func _removeWatcher()
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSFunction? { get set }
}

// MARK: - Module implementation

@_documentation(visibility: private)
@MainActor
@objc class HSLocaleModule: NSObject, HSModuleAPI, HSLocaleModuleAPI {
    var moduleName = "hs.locale"
    let engineID: UUID

    // MARK: - Watcher (Pattern A)
    @objc var _watcherEmitter: JSFunction? = nil
    private var watcherCallback: JSFunction?
    private var localeChangeObserver: NSObjectProtocol?

    // MARK: - Lifecycle

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKDebug("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        _removeWatcher()
        _watcherEmitter = nil
    }

    isolated deinit {
        AKDebug("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        return "<\(moduleName): \(current())>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - HSLocaleModuleAPI

    func availableLocales() -> [String] {
        Locale.availableIdentifiers
    }

    func current() -> String {
        Locale.current.identifier
    }

    func preferredLanguages() -> [String] {
        Locale.preferredLanguages
    }

    func details(_ identifier: String?) -> [String: Any] {
        let locale: Locale
        switch identifier {
        case nil, "", "undefined", "null":
            locale = Locale.current
        default:
            locale = Locale(identifier: identifier!)
        }
        return localeDetails(locale)
    }

    func localizedName(_ localeCode: String, _ baseLocaleCode: String?) -> [String: String]? {
        let available = Locale.availableIdentifiers
        guard available.contains(localeCode) else { return nil }

        let baseLocale: Locale
        switch baseLocaleCode {
        case nil, "", "undefined", "null":
            baseLocale = Locale.current
        default:
            guard available.contains(baseLocaleCode!) else { return nil }
            baseLocale = Locale(identifier: baseLocaleCode!)
        }

        guard let localName = baseLocale.localizedString(forLanguageCode: localeCode),
              let nameWithDialect = baseLocale.localizedString(forIdentifier: localeCode) else {
            return nil
        }

        return ["name": localName, "nameWithDialect": nameWithDialect]
    }

    // MARK: - Watcher (Pattern A)

    func addWatcher(_ listener: JSFunction) {
        _watcherEmitter?.invokeMethod("on", withArguments: [listener])
    }

    func removeWatcher(_ listener: JSFunction) {
        _watcherEmitter?.invokeMethod("removeListener", withArguments: [listener])
    }

    @objc(_addWatcher:) func _addWatcher(_ callback: JSFunction) {
        guard watcherCallback == nil else {
            AKWarning("hs.locale._addWatcher: already watching — refusing second subscription")
            return
        }
        watcherCallback = callback
        localeChangeObserver = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.localeDidChange() }
        }
        AKTrace("hs.locale._addWatcher: started")
    }

    @objc func _removeWatcher() {
        if let observer = localeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            localeChangeObserver = nil
        }
        watcherCallback = nil
        AKTrace("hs.locale._removeWatcher: stopped")
    }

    private func localeDidChange() {
        _ = watcherCallback?.call(withArguments: [])
    }
}
