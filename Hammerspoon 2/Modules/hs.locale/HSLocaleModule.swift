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
/// hs.locale.on('change', () => {
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

    // MARK: Watcher

    // NOTE: Private API consumed only by hs.locale.js
    /// SKIP_DOCS
    @objc(_addWatcher:) func _addWatcher(_ callback: JSFunction)
    /// SKIP_DOCS
    @objc func _removeWatcher()
    /// SKIP_DOCS
    @objc var _watcherEmitter: JSFunction? { get set }

    /// The event names `on()`/`once()` accept - see HSLocaleEvent
    /// SKIP_DOCS
    @objc var _eventNames: [String] { get }

    // MARK: - Swift-retained storage for JS-defined enhancements
    // These are set by hs.locale.js. They must be real, pre-declared properties (not
    // dynamically-added JS properties) or JavaScriptCore silently drops them the first time
    // it garbage collects the wrapper it created for this object - see issue #185.

    /// SKIP_DOCS
    @objc var on: JSFunction? { get set }
    /// SKIP_DOCS
    @objc var off: JSFunction? { get set }
    /// SKIP_DOCS
    @objc var once: JSFunction? { get set }
}

// MARK: - Module implementation

/// Events emitted by hs.locale's watcher
nonisolated enum HSLocaleEvent: String, HSEventName {
    case change
}

@_documentation(visibility: private)
@MainActor
@objc class HSLocaleModule: NSObject, HSModuleAPI, HSLocaleModuleAPI {
    var moduleName = "hs.locale"
    let engineID: UUID

    // MARK: - Watcher
    @objc var _watcherEmitter: JSFunction? = nil
    @objc var _eventNames: [String] { HSLocaleEvent.allNames }
    @objc var on: JSFunction? = nil
    @objc var off: JSFunction? = nil
    @objc var once: JSFunction? = nil
    private var watcherCallback: JSFunction?
    private var localeChangeObserver: NSObjectProtocol?

    // MARK: - Lifecycle

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        _removeWatcher()
        _watcherEmitter = nil
        on = nil
        off = nil
        once = nil
    }

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
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

    // MARK: - Watcher

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
        AKDebug("hs.locale._addWatcher: started")
    }

    @objc func _removeWatcher() {
        if let observer = localeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            localeChangeObserver = nil
        }
        watcherCallback = nil
        AKDebug("hs.locale._removeWatcher: stopped")
    }

    private func localeDidChange() {
        _ = watcherCallback?.call(withArguments: [HSLocaleEvent.change.rawValue])
    }
}
