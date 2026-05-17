"use strict";

// Wrap createService so `domain` defaults to "local." if omitted.
(function () {
    const _native = hs.bonjour.createService.bind(hs.bonjour);
    hs.bonjour.createService = function (name, type, port, domain) {
        return _native(name, type, port, domain !== undefined ? domain : "local.");
    };
})();

// Wrap networkServices so `timeout` defaults to 5 seconds if omitted.
(function () {
    const _native = hs.bonjour.networkServices.bind(hs.bonjour);
    hs.bonjour.networkServices = function (timeout) {
        return _native(typeof timeout === "number" ? timeout : 5.0);
    };
})();

// Common Bonjour/mDNS service type strings.
// Source: http://www.dns-sd.org/ServiceTypes.html
hs.bonjour.serviceTypes = Object.freeze({
    airplay:        "_airplay._tcp.",
    airport:        "_airport._tcp.",
    afp:            "_afpovertcp._tcp.",
    daap:           "_daap._tcp.",
    ftp:            "_ftp._tcp.",
    googleCast:     "_googlecast._tcp.",
    homekit:        "_hap._tcp.",
    http:           "_http._tcp.",
    https:          "_https._tcp.",
    ipp:            "_ipp._tcp.",
    ipps:           "_ipps._tcp.",
    nfs:            "_nfs._tcp.",
    printer:        "_printer._tcp.",
    raop:           "_raop._tcp.",
    rdp:            "_rdp._tcp.",
    sftp:           "_sftp-ssh._tcp.",
    smb:            "_smb._tcp.",
    smtp:           "_smtp._tcp.",
    snmp:           "_snmp._udp.",
    ssh:            "_ssh._tcp.",
    telnet:         "_telnet._tcp.",
    vnc:            "_rfb._tcp.",
    workstation:    "_workstation._tcp.",
});
