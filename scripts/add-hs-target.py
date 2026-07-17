#!/usr/bin/env python3
"""
Add the 'hs' command-line tool target to Hammerspoon 2.xcodeproj/project.pbxproj.
Run from the repo root:  python3 scripts/add-hs-target.py
"""

import os, sys, re, shutil

PBXPROJ = os.path.join(os.path.dirname(__file__), '..', 'Hammerspoon 2.xcodeproj', 'project.pbxproj')
PBXPROJ = os.path.normpath(PBXPROJ)

# ── Fixed UUIDs for every new pbxproj object ─────────────────────────────────
UUID_HS_PRODUCT         = '4FE4C0012F00000000000001'  # PBXFileReference: hs (tool)
UUID_HS_FSSRG           = '4FE4C0022F00000000000002'  # PBXFileSystemSynchronizedRootGroup: hs/
UUID_HS_TARGET          = '4FE4C0032F00000000000003'  # PBXNativeTarget: hs
UUID_HS_SOURCES         = '4FE4C0042F00000000000004'  # PBXSourcesBuildPhase
UUID_HS_FRAMEWORKS      = '4FE4C0052F00000000000005'  # PBXFrameworksBuildPhase
UUID_HS_RESOURCES       = '4FE4C0062F00000000000006'  # PBXResourcesBuildPhase
UUID_HS_DEBUG           = '4FE4C0072F00000000000007'  # XCBuildConfiguration Debug
UUID_HS_RELEASE         = '4FE4C0082F00000000000008'  # XCBuildConfiguration Release
UUID_HS_CONFIGLIST      = '4FE4C0092F00000000000009'  # XCConfigurationList
UUID_PROXY_APP_TO_HS    = '4FE4C00A2F0000000000000A'  # PBXContainerItemProxy (app → hs)
UUID_DEP_APP_TO_HS      = '4FE4C00B2F0000000000000B'  # PBXTargetDependency
UUID_BF_HS_EMBED        = '4FE4C00C2F0000000000000C'  # PBXBuildFile (hs in embed tools)
UUID_EMBED_TOOLS        = '4FE4C00D2F0000000000000D'  # PBXCopyFilesBuildPhase

# Known UUIDs from existing project
UUID_MAIN_APP           = '4F5641822E8333830099EB4C'
UUID_MAIN_APP_SOURCES   = '4F56417F2E8333830099EB4C'
UUID_MAIN_APP_TARGET    = '4F5641822E8333830099EB4C'

def read():
    with open(PBXPROJ, 'r', encoding='utf-8') as f:
        return f.read()

def write(content):
    backup = PBXPROJ + '.bak'
    if not os.path.exists(backup):
        shutil.copy2(PBXPROJ, backup)
        print(f'  Backup created at {backup}')
    with open(PBXPROJ, 'w', encoding='utf-8') as f:
        f.write(content)

def already_patched(content):
    return UUID_HS_TARGET in content

# ── Snippet builders ──────────────────────────────────────────────────────────

def pbx_build_file():
    return f'\t\t{UUID_BF_HS_EMBED} /* hs in Embed Tools */ = {{isa = PBXBuildFile; fileRef = {UUID_HS_PRODUCT} /* hs */; settings = {{ATTRIBUTES = (CodeSignOnCopy, ); }}; }};\n'

def pbx_file_reference():
    return f'\t\t{UUID_HS_PRODUCT} /* hs */ = {{isa = PBXFileReference; explicitFileType = "compiled.mach-o.executable"; includeInIndex = 0; path = hs; sourceTree = BUILT_PRODUCTS_DIR; }};\n'

def pbx_fssrg():
    return f'\t\t{UUID_HS_FSSRG} /* hs */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\tpath = hs;\n\t\t\tsourceTree = "<group>";\n\t\t}};\n'

def pbx_frameworks_phase():
    return (
        f'\t\t{UUID_HS_FRAMEWORKS} /* Frameworks */ = {{\n'
        f'\t\t\tisa = PBXFrameworksBuildPhase;\n'
        f'\t\t\tbuildActionMask = 2147483647;\n'
        f'\t\t\tfiles = (\n'
        f'\t\t\t);\n'
        f'\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
        f'\t\t}};\n'
    )

def pbx_native_target():
    return (
        f'\t\t{UUID_HS_TARGET} /* hs */ = {{\n'
        f'\t\t\tisa = PBXNativeTarget;\n'
        f'\t\t\tbuildConfigurationList = {UUID_HS_CONFIGLIST} /* Build configuration list for PBXNativeTarget "hs" */;\n'
        f'\t\t\tbuildPhases = (\n'
        f'\t\t\t\t{UUID_HS_SOURCES} /* Sources */,\n'
        f'\t\t\t\t{UUID_HS_FRAMEWORKS} /* Frameworks */,\n'
        f'\t\t\t\t{UUID_HS_RESOURCES} /* Resources */,\n'
        f'\t\t\t);\n'
        f'\t\t\tbuildRules = (\n'
        f'\t\t\t);\n'
        f'\t\t\tdependencies = (\n'
        f'\t\t\t);\n'
        f'\t\t\tfileSystemSynchronizedGroups = (\n'
        f'\t\t\t\t{UUID_HS_FSSRG} /* hs */,\n'
        f'\t\t\t);\n'
        f'\t\t\tname = hs;\n'
        f'\t\t\tpackageProductDependencies = (\n'
        f'\t\t\t);\n'
        f'\t\t\tproductName = hs;\n'
        f'\t\t\tproductReference = {UUID_HS_PRODUCT} /* hs */;\n'
        f'\t\t\tproductType = "com.apple.product-type.tool";\n'
        f'\t\t}};\n'
    )

def pbx_container_proxy():
    return (
        f'\t\t{UUID_PROXY_APP_TO_HS} /* PBXContainerItemProxy */ = {{\n'
        f'\t\t\tisa = PBXContainerItemProxy;\n'
        f'\t\t\tcontainerPortal = 4F56417B2E8333830099EB4C /* Project object */;\n'
        f'\t\t\tproxyType = 1;\n'
        f'\t\t\tremoteGlobalIDString = {UUID_HS_TARGET};\n'
        f'\t\t\tremoteInfo = hs;\n'
        f'\t\t}};\n'
    )

def pbx_target_dependency():
    return (
        f'\t\t{UUID_DEP_APP_TO_HS} /* PBXTargetDependency */ = {{\n'
        f'\t\t\tisa = PBXTargetDependency;\n'
        f'\t\t\ttarget = {UUID_HS_TARGET} /* hs */;\n'
        f'\t\t\ttargetProxy = {UUID_PROXY_APP_TO_HS} /* PBXContainerItemProxy */;\n'
        f'\t\t}};\n'
    )

def pbx_resources_phase():
    return (
        f'\t\t{UUID_HS_RESOURCES} /* Resources */ = {{\n'
        f'\t\t\tisa = PBXResourcesBuildPhase;\n'
        f'\t\t\tbuildActionMask = 2147483647;\n'
        f'\t\t\tfiles = (\n'
        f'\t\t\t);\n'
        f'\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
        f'\t\t}};\n'
    )

def pbx_sources_phase():
    return (
        f'\t\t{UUID_HS_SOURCES} /* Sources */ = {{\n'
        f'\t\t\tisa = PBXSourcesBuildPhase;\n'
        f'\t\t\tbuildActionMask = 2147483647;\n'
        f'\t\t\tfiles = (\n'
        f'\t\t\t);\n'
        f'\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
        f'\t\t}};\n'
    )

def xc_build_config_debug():
    return (
        f'\t\t{UUID_HS_DEBUG} /* Debug */ = {{\n'
        f'\t\t\tisa = XCBuildConfiguration;\n'
        f'\t\t\tbuildSettings = {{\n'
        f'\t\t\t\tCODE_SIGN_STYLE = Automatic;\n'
        f'\t\t\t\tCURRENT_PROJECT_VERSION = 1;\n'
        f'\t\t\t\tDEAD_CODE_STRIPPING = YES;\n'
        f'\t\t\t\tDEVELOPMENT_TEAM = VQCYSNZB89;\n'
        f'\t\t\t\tENABLE_HARDENED_RUNTIME = YES;\n'
        f'\t\t\t\tGCC_TREAT_WARNINGS_AS_ERRORS = YES;\n'
        f'\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n'
        f'\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 15.6;\n'
        f'\t\t\t\tMARKETING_VERSION = 1.0;\n'
        f'\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "net.tenshu.Hammerspoon-2.hs";\n'
        f'\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";\n'
        f'\t\t\t\tSKIP_INSTALL = YES;\n'
        f'\t\t\t\tSTRING_CATALOG_GENERATE_SYMBOLS = NO;\n'
        f'\t\t\t\tSWIFT_APPROACHABLE_CONCURRENCY = YES;\n'
        f'\t\t\t\tSWIFT_EMIT_LOC_STRINGS = NO;\n'
        f'\t\t\t\tSWIFT_STRICT_CONCURRENCY = complete;\n'
        f'\t\t\t\tSWIFT_STRICT_MEMORY_SAFETY = YES;\n'
        f'\t\t\t\tSWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;\n'
        f'\t\t\t\tSWIFT_VERSION = 6.0;\n'
        f'\t\t\t}};\n'
        f'\t\t\tname = Debug;\n'
        f'\t\t}};\n'
    )

def xc_build_config_release():
    return (
        f'\t\t{UUID_HS_RELEASE} /* Release */ = {{\n'
        f'\t\t\tisa = XCBuildConfiguration;\n'
        f'\t\t\tbuildSettings = {{\n'
        f'\t\t\t\tCODE_SIGN_STYLE = Automatic;\n'
        f'\t\t\t\tCURRENT_PROJECT_VERSION = 1;\n'
        f'\t\t\t\tDEAD_CODE_STRIPPING = YES;\n'
        f'\t\t\t\tDEVELOPMENT_TEAM = VQCYSNZB89;\n'
        f'\t\t\t\tENABLE_HARDENED_RUNTIME = YES;\n'
        f'\t\t\t\tGCC_TREAT_WARNINGS_AS_ERRORS = YES;\n'
        f'\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n'
        f'\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 15.6;\n'
        f'\t\t\t\tMARKETING_VERSION = 1.0;\n'
        f'\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "net.tenshu.Hammerspoon-2.hs";\n'
        f'\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";\n'
        f'\t\t\t\tSKIP_INSTALL = YES;\n'
        f'\t\t\t\tSTRING_CATALOG_GENERATE_SYMBOLS = NO;\n'
        f'\t\t\t\tSWIFT_APPROACHABLE_CONCURRENCY = YES;\n'
        f'\t\t\t\tSWIFT_EMIT_LOC_STRINGS = NO;\n'
        f'\t\t\t\tSWIFT_STRICT_CONCURRENCY = complete;\n'
        f'\t\t\t\tSWIFT_STRICT_MEMORY_SAFETY = YES;\n'
        f'\t\t\t\tSWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;\n'
        f'\t\t\t\tSWIFT_VERSION = 6.0;\n'
        f'\t\t\t}};\n'
        f'\t\t\tname = Release;\n'
        f'\t\t}};\n'
    )

def xc_config_list():
    return (
        f'\t\t{UUID_HS_CONFIGLIST} /* Build configuration list for PBXNativeTarget "hs" */ = {{\n'
        f'\t\t\tisa = XCConfigurationList;\n'
        f'\t\t\tbuildConfigurations = (\n'
        f'\t\t\t\t{UUID_HS_DEBUG} /* Debug */,\n'
        f'\t\t\t\t{UUID_HS_RELEASE} /* Release */,\n'
        f'\t\t\t);\n'
        f'\t\t\tdefaultConfigurationIsVisible = 0;\n'
        f'\t\t\tdefaultConfigurationName = Release;\n'
        f'\t\t}};\n'
    )

def embed_tools_phase():
    return (
        f'\t\t{UUID_EMBED_TOOLS} /* Embed Tools */ = {{\n'
        f'\t\t\tisa = PBXCopyFilesBuildPhase;\n'
        f'\t\t\tbuildActionMask = 2147483647;\n'
        f'\t\t\tdstPath = "";\n'
        f'\t\t\tdstSubfolderSpec = 6;\n'
        f'\t\t\tfiles = (\n'
        f'\t\t\t\t{UUID_BF_HS_EMBED} /* hs in Embed Tools */,\n'
        f'\t\t\t);\n'
        f'\t\t\tname = "Embed Tools";\n'
        f'\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
        f'\t\t}};\n'
    )

# ── Patch functions ───────────────────────────────────────────────────────────

def insert_after_marker(content, marker, insertion):
    """Insert `insertion` immediately after `marker` (and any trailing newline)."""
    idx = content.find(marker)
    if idx == -1:
        raise ValueError(f'Marker not found: {marker!r}')
    after = idx + len(marker)
    # Step over a single newline that directly follows the marker.
    if after < len(content) and content[after] == '\n':
        after += 1
    return content[:after] + insertion + content[after:]

def patch(content):
    # 1. PBXBuildFile section — add embed build file
    content = insert_after_marker(
        content,
        '/* Begin PBXBuildFile section */',
        pbx_build_file()
    )

    # 2. PBXContainerItemProxy section — add proxy for app→hs dependency
    content = insert_after_marker(
        content,
        '/* Begin PBXContainerItemProxy section */',
        pbx_container_proxy()
    )

    # 3. PBXCopyFilesBuildPhase section — add embed tools phase
    content = insert_after_marker(
        content,
        '/* Begin PBXCopyFilesBuildPhase section */',
        embed_tools_phase()
    )

    # 4. PBXFileReference section — add hs product reference
    content = insert_after_marker(
        content,
        '/* Begin PBXFileReference section */',
        pbx_file_reference()
    )

    # 5. PBXFileSystemSynchronizedRootGroup section — add hs/ directory group
    content = insert_after_marker(
        content,
        '/* Begin PBXFileSystemSynchronizedRootGroup section */',
        pbx_fssrg()
    )

    # 6. PBXFrameworksBuildPhase section — add hs frameworks phase
    content = insert_after_marker(
        content,
        '/* Begin PBXFrameworksBuildPhase section */',
        pbx_frameworks_phase()
    )

    # 7. Products group — add hs product reference
    products_marker = '\t\t\t\t4F947D872F563FCF00DD814E /* HammerspoonOSAScriptHelper.xpc */,'
    hs_product_entry = f'\t\t\t\t{UUID_HS_PRODUCT} /* hs */,\n'
    content = insert_after_marker(content, products_marker, hs_product_entry)

    # 8. Root group children — add hs directory group
    root_group_marker = '\t\t\t\t4F947D882F563FCF00DD814E /* HammerspoonOSAScriptHelper */,'
    hs_group_entry = f'\t\t\t\t{UUID_HS_FSSRG} /* hs */,\n'
    content = insert_after_marker(content, root_group_marker, hs_group_entry)

    # 9. PBXNativeTarget section — add hs target
    content = insert_after_marker(
        content,
        '/* Begin PBXNativeTarget section */',
        pbx_native_target()
    )

    # 10. PBXProject targets list — add hs target
    existing_target_line = f'\t\t\t\t{UUID_HS_TARGET} /* hs */,\n'
    targets_marker = f'\t\t\t\t4F947D862F563FCF00DD814E /* HammerspoonOSAScriptHelper */,'
    content = insert_after_marker(content, targets_marker, existing_target_line)

    # 11. PBXProject TargetAttributes — add entry for hs (5-tab indentation)
    ta_marker = '\t\t\t\t\t4F947D862F563FCF00DD814E = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;\n\t\t\t\t\t};'
    hs_ta = (
        f'\t\t\t\t\t{UUID_HS_TARGET} = {{\n'
        f'\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;\n'
        f'\t\t\t\t\t}};\n'
    )
    content = insert_after_marker(content, ta_marker, hs_ta)

    # 12. PBXResourcesBuildPhase section — add hs resources phase
    content = insert_after_marker(
        content,
        '/* Begin PBXResourcesBuildPhase section */',
        pbx_resources_phase()
    )

    # 13. PBXSourcesBuildPhase section — add hs sources phase
    content = insert_after_marker(
        content,
        '/* Begin PBXSourcesBuildPhase section */',
        pbx_sources_phase()
    )

    # 14. PBXTargetDependency section — add hs dependency entry
    content = insert_after_marker(
        content,
        '/* Begin PBXTargetDependency section */',
        pbx_target_dependency()
    )

    # 15. "Hammerspoon 2" target buildPhases — add embed tools phase
    embed_xpc_line = f'\t\t\t\t4F947D932F563FCF00DD814E /* Embed XPC Services */,'
    embed_tools_entry = f'\t\t\t\t{UUID_EMBED_TOOLS} /* Embed Tools */,\n'
    content = insert_after_marker(content, embed_xpc_line, embed_tools_entry)

    # 16. "Hammerspoon 2" target dependencies — add hs dependency
    existing_dep_line = '\t\t\t\t4F947D912F563FCF00DD814E /* PBXTargetDependency */,'
    hs_dep_entry = f'\t\t\t\t{UUID_DEP_APP_TO_HS} /* PBXTargetDependency */,\n'
    content = insert_after_marker(content, existing_dep_line, hs_dep_entry)

    # 17. XCBuildConfiguration section — add Debug and Release configs for hs
    content = insert_after_marker(
        content,
        '/* Begin XCBuildConfiguration section */',
        xc_build_config_debug() + xc_build_config_release()
    )

    # 18. XCConfigurationList section — add config list for hs
    content = insert_after_marker(
        content,
        '/* Begin XCConfigurationList section */',
        xc_config_list()
    )

    return content

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    print(f'Patching {PBXPROJ}')
    content = read()

    if already_patched(content):
        print('  Already patched — nothing to do.')
        return

    try:
        patched = patch(content)
    except ValueError as e:
        print(f'  ERROR: {e}')
        print('  The project file may have changed. Patch aborted — no changes written.')
        sys.exit(1)

    write(patched)
    print('  Done. Open Xcode to verify the new "hs" target.')
    print()
    print('  Next steps in Xcode:')
    print('  1. Select the "hs" target → General → verify deployment target is 15.6')
    print('  2. Select the "Hammerspoon 2" target → Build Phases → "Embed Tools"')
    print('     Confirm "hs" is listed with Code Sign on Copy enabled.')
    print('  3. Build both targets.')

if __name__ == '__main__':
    main()
