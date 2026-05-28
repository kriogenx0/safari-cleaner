#!/usr/bin/env python3
"""
Generates the complete Xcode project for Safari Swipe.
Run from /Users/alexv/Sites/safari-swipe:
    python3 generate_project.py
"""
import os, uuid, shutil, plistlib
from pathlib import Path

ROOT = Path(__file__).parent
EXT_SRC = ROOT / "extension"
PROJ_DIR = ROOT / "SafariSwipe"

APP_NAME      = "Safari Swipe"
APP_ID_SAFE   = "SafariSwipe"
BUNDLE_ID_APP = "com.alexv.safari-swipe"
BUNDLE_ID_EXT = "com.alexv.safari-swipe.Extension"
DEPLOY_TARGET = "14.0"
SWIFT_VERSION = "5.0"

def uid():
    return uuid.uuid4().hex[:24].upper()

# ── IDs ──────────────────────────────────────────────────────────────────────
IDS = {k: uid() for k in [
    "project",
    "main_group", "app_group", "ext_group", "res_group", "products_group",
    "app_target", "ext_target",
    # app source files
    "ref_appdel", "ref_viewctl", "ref_app_info", "ref_app_ent", "ref_main_storyboard",
    "ref_assets",
    # ext source files
    "ref_exthandler", "ref_ext_info", "ref_ext_ent",
    # ext resources (copies of web ext files)
    "ref_manifest", "ref_background", "ref_content",
    "ref_icon48", "ref_icon96", "ref_icon128", "ref_icon256",
    # app product
    "product_app",
    # ext product
    "product_ext",
    # build files (sources)
    "bf_appdel", "bf_viewctl", "bf_exthandler",
    # build files (resources)
    "bf_main_storyboard", "bf_assets",
    "bf_manifest", "bf_background", "bf_content",
    "bf_icon48", "bf_icon96", "bf_icon128", "bf_icon256",
    # build phases
    "bp_app_sources", "bp_app_resources", "bp_app_frameworks",
    "bp_ext_sources", "bp_ext_resources", "bp_ext_frameworks",
    "bp_app_embed",
    # build configs
    "bc_app_debug", "bc_app_release",
    "bc_ext_debug", "bc_ext_release",
    "bc_proj_debug", "bc_proj_release",
    # config lists
    "cl_project", "cl_app", "cl_ext",
    # dependency
    "dep_ext", "proxy_ext",
    # embed
    "bf_embed_ext",
]}
I = IDS

def pbx_file_ref(uid, name, path, file_type, source_tree='"<group>"'):
    return (f'\t\t{uid} = {{\n'
            f'\t\t\tisa = PBXFileReference;\n'
            f'\t\t\tlastKnownFileType = {file_type};\n'
            f'\t\t\tname = "{name}";\n'
            f'\t\t\tpath = "{path}";\n'
            f'\t\t\tsourceTree = {source_tree};\n'
            f'\t\t}};\n')

def pbx_build_file(uid, ref_uid, settings=""):
    s = f'\t\t{uid} = {{\n\t\t\tisa = PBXBuildFile;\n\t\t\tfileRef = {ref_uid};\n'
    if settings:
        s += f'\t\t\tsettings = {{{settings}}};\n'
    s += '\t\t};\n'
    return s

def write_project():
    p = PROJ_DIR / f"{APP_ID_SAFE}.xcodeproj"
    p.mkdir(parents=True, exist_ok=True)

    pbxproj = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{pbx_build_file(I['bf_appdel'],    I['ref_appdel'])}
{pbx_build_file(I['bf_viewctl'],   I['ref_viewctl'])}
{pbx_build_file(I['bf_exthandler'],I['ref_exthandler'])}
{pbx_build_file(I['bf_main_storyboard'], I['ref_main_storyboard'])}
{pbx_build_file(I['bf_assets'],    I['ref_assets'])}
{pbx_build_file(I['bf_manifest'],  I['ref_manifest'])}
{pbx_build_file(I['bf_background'],I['ref_background'])}
{pbx_build_file(I['bf_content'],   I['ref_content'])}
{pbx_build_file(I['bf_icon48'],    I['ref_icon48'])}
{pbx_build_file(I['bf_icon96'],    I['ref_icon96'])}
{pbx_build_file(I['bf_icon128'],   I['ref_icon128'])}
{pbx_build_file(I['bf_icon256'],   I['ref_icon256'])}
\t\t{I['bf_embed_ext']} = {{
\t\t\tisa = PBXBuildFile;
\t\t\tfileRef = {I['product_ext']};
\t\t\tsettings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }};
\t\t}};
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
\t\t{I['proxy_ext']} = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {I['project']};
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {I['ext_target']};
\t\t\tremoteInfo = "{APP_NAME} Extension";
\t\t}};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
\t\t{I['bp_app_embed']} = {{
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "";
\t\t\tdstSubfolderSpec = 13;
\t\t\tfiles = (
\t\t\t\t{I['bf_embed_ext']},
\t\t\t);
\t\t\tname = "Embed Foundation Extensions";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
{pbx_file_ref(I['product_app'],   f"{APP_NAME}.app",           f"{APP_NAME}.app",     "wrapper.application", "BUILT_PRODUCTS_DIR")}
{pbx_file_ref(I['product_ext'],   f"{APP_NAME} Extension.appex", f"{APP_NAME} Extension.appex", "wrapper.app-extension", "BUILT_PRODUCTS_DIR")}
{pbx_file_ref(I['ref_appdel'],    "AppDelegate.swift",         "AppDelegate.swift",   "sourcecode.swift")}
{pbx_file_ref(I['ref_viewctl'],   "ViewController.swift",      "ViewController.swift","sourcecode.swift")}
{pbx_file_ref(I['ref_app_info'],  "Info.plist",                "Info.plist",          "text.plist.xml")}
{pbx_file_ref(I['ref_app_ent'],   f"{APP_ID_SAFE}.entitlements", f"{APP_ID_SAFE}.entitlements", "text.plist.entitlements")}
{pbx_file_ref(I['ref_main_storyboard'], "Main.storyboard",     "Base.lproj/Main.storyboard", "file.storyboard")}
{pbx_file_ref(I['ref_assets'],    "Assets.xcassets",           "Assets.xcassets",     "folder.assetcatalog")}
{pbx_file_ref(I['ref_exthandler'],"SafariWebExtensionHandler.swift","SafariWebExtensionHandler.swift","sourcecode.swift")}
{pbx_file_ref(I['ref_ext_info'],  "Info.plist",                "Info.plist",          "text.plist.xml")}
{pbx_file_ref(I['ref_ext_ent'],   f"{APP_ID_SAFE}Extension.entitlements", f"{APP_ID_SAFE}Extension.entitlements", "text.plist.entitlements")}
{pbx_file_ref(I['ref_manifest'],  "manifest.json",             "Resources/manifest.json",  "text.json")}
{pbx_file_ref(I['ref_background'],"background.js",             "Resources/background.js",  "sourcecode.javascript")}
{pbx_file_ref(I['ref_content'],   "content.js",                "Resources/content.js",     "sourcecode.javascript")}
{pbx_file_ref(I['ref_icon48'],    "icon-48.png",               "Resources/images/icon-48.png",  "image.png")}
{pbx_file_ref(I['ref_icon96'],    "icon-96.png",               "Resources/images/icon-96.png",  "image.png")}
{pbx_file_ref(I['ref_icon128'],   "icon-128.png",              "Resources/images/icon-128.png", "image.png")}
{pbx_file_ref(I['ref_icon256'],   "icon-256.png",              "Resources/images/icon-256.png", "image.png")}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{I['bp_app_frameworks']} = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = ();
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{I['bp_ext_frameworks']} = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = ();
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{I['main_group']} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{I['app_group']},
\t\t\t\t{I['ext_group']},
\t\t\t\t{I['products_group']},
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{I['products_group']} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{I['product_app']},
\t\t\t\t{I['product_ext']},
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{I['app_group']} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{I['ref_appdel']},
\t\t\t\t{I['ref_viewctl']},
\t\t\t\t{I['ref_main_storyboard']},
\t\t\t\t{I['ref_assets']},
\t\t\t\t{I['ref_app_info']},
\t\t\t\t{I['ref_app_ent']},
\t\t\t);
\t\t\tname = "{APP_NAME}";
\t\t\tpath = "{APP_NAME}";
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{I['ext_group']} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{I['ref_exthandler']},
\t\t\t\t{I['res_group']},
\t\t\t\t{I['ref_ext_info']},
\t\t\t\t{I['ref_ext_ent']},
\t\t\t);
\t\t\tname = "{APP_NAME} Extension";
\t\t\tpath = "{APP_NAME} Extension";
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{I['res_group']} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{I['ref_manifest']},
\t\t\t\t{I['ref_background']},
\t\t\t\t{I['ref_content']},
\t\t\t\t{I['ref_icon48']},
\t\t\t\t{I['ref_icon96']},
\t\t\t\t{I['ref_icon128']},
\t\t\t\t{I['ref_icon256']},
\t\t\t);
\t\t\tname = Resources;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{I['app_target']} = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {I['cl_app']};
\t\t\tbuildPhases = (
\t\t\t\t{I['bp_app_sources']},
\t\t\t\t{I['bp_app_resources']},
\t\t\t\t{I['bp_app_frameworks']},
\t\t\t\t{I['bp_app_embed']},
\t\t\t);
\t\t\tbuildRules = ();
\t\t\tdependencies = (
\t\t\t\t{I['dep_ext']},
\t\t\t);
\t\t\tname = "{APP_NAME}";
\t\t\tproductName = "{APP_NAME}";
\t\t\tproductReference = {I['product_app']};
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
\t\t{I['ext_target']} = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {I['cl_ext']};
\t\t\tbuildPhases = (
\t\t\t\t{I['bp_ext_sources']},
\t\t\t\t{I['bp_ext_resources']},
\t\t\t\t{I['bp_ext_frameworks']},
\t\t\t);
\t\t\tbuildRules = ();
\t\t\tdependencies = ();
\t\t\tname = "{APP_NAME} Extension";
\t\t\tproductName = "{APP_NAME} Extension";
\t\t\tproductReference = {I['product_ext']};
\t\t\tproductType = "com.apple.product-type.app-extension";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{I['project']} = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1500;
\t\t\t\tLastUpgradeCheck = 1500;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{I['app_target']} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t}};
\t\t\t\t\t{I['ext_target']} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {I['cl_project']};
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {I['main_group']};
\t\t\tproductRefGroup = {I['products_group']};
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{I['app_target']},
\t\t\t\t{I['ext_target']},
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{I['bp_app_resources']} = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{I['bf_main_storyboard']},
\t\t\t\t{I['bf_assets']},
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{I['bp_ext_resources']} = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{I['bf_manifest']},
\t\t\t\t{I['bf_background']},
\t\t\t\t{I['bf_content']},
\t\t\t\t{I['bf_icon48']},
\t\t\t\t{I['bf_icon96']},
\t\t\t\t{I['bf_icon128']},
\t\t\t\t{I['bf_icon256']},
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{I['bp_app_sources']} = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{I['bf_appdel']},
\t\t\t\t{I['bf_viewctl']},
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{I['bp_ext_sources']} = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{I['bf_exthandler']},
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
\t\t{I['dep_ext']} = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {I['ext_target']};
\t\t\ttargetProxy = {I['proxy_ext']};
\t\t}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
\t\t{I['bc_proj_debug']} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = {DEPLOY_TARGET};
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{I['bc_proj_release']} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = {DEPLOY_TARGET};
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Owholemodule";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{I['bc_app_debug']} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSET_CATALOG_COMPILER_OPTIMIZATION = space;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = "{APP_NAME}/{APP_ID_SAFE}.entitlements";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tINFOPLIST_FILE = "{APP_NAME}/Info.plist";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = "@executable_path/../Frameworks";
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = {DEPLOY_TARGET};
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "{BUNDLE_ID_APP}";
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_VERSION = {SWIFT_VERSION};
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{I['bc_app_release']} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSET_CATALOG_COMPILER_OPTIMIZATION = space;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = "{APP_NAME}/{APP_ID_SAFE}.entitlements";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tINFOPLIST_FILE = "{APP_NAME}/Info.plist";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = "@executable_path/../Frameworks";
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = {DEPLOY_TARGET};
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "{BUNDLE_ID_APP}";
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_VERSION = {SWIFT_VERSION};
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{I['bc_ext_debug']} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_ENTITLEMENTS = "{APP_NAME} Extension/{APP_ID_SAFE}Extension.entitlements";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tINFOPLIST_FILE = "{APP_NAME} Extension/Info.plist";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = "@executable_path/../Frameworks";
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = {DEPLOY_TARGET};
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "{BUNDLE_ID_EXT}";
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSWIFT_VERSION = {SWIFT_VERSION};
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{I['bc_ext_release']} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_ENTITLEMENTS = "{APP_NAME} Extension/{APP_ID_SAFE}Extension.entitlements";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tINFOPLIST_FILE = "{APP_NAME} Extension/Info.plist";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = "@executable_path/../Frameworks";
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = {DEPLOY_TARGET};
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "{BUNDLE_ID_EXT}";
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSWIFT_VERSION = {SWIFT_VERSION};
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{I['cl_project']} = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{I['bc_proj_debug']},
\t\t\t\t{I['bc_proj_release']},
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{I['cl_app']} = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{I['bc_app_debug']},
\t\t\t\t{I['bc_app_release']},
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{I['cl_ext']} = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{I['bc_ext_debug']},
\t\t\t\t{I['bc_ext_release']},
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */

\t}};
\trootObject = {I['project']};
}}
"""
    with open(p / "project.pbxproj", "w") as f:
        f.write(pbxproj)
    print(f"  {p}/project.pbxproj")

def write_app_sources():
    d = PROJ_DIR / APP_NAME
    d.mkdir(parents=True, exist_ok=True)

    (d / "AppDelegate.swift").write_text("""\
import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {}
    func applicationWillTerminate(_ n: Notification) {}
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
""")

    (d / "ViewController.swift").write_text(f"""\
import Cocoa
import SafariServices

class ViewController: NSViewController {{
    override func viewDidLoad() {{
        super.viewDidLoad()
    }}
    @IBAction func openExtensionPrefs(_ sender: Any?) {{
        SFSafariApplication.showPreferencesForExtension(withIdentifier: "{BUNDLE_ID_EXT}") {{ _ in }}
    }}
}}
""")

    # Info.plist
    plist = dict(
        CFBundleDevelopmentRegion="$(DEVELOPMENT_LANGUAGE)",
        CFBundleExecutable="$(EXECUTABLE_NAME)",
        CFBundleIconFile="",
        CFBundleIdentifier="$(PRODUCT_BUNDLE_IDENTIFIER)",
        CFBundleInfoDictionaryVersion="6.0",
        CFBundleName="$(PRODUCT_NAME)",
        CFBundlePackageType="$(PRODUCT_BUNDLE_PACKAGE_TYPE)",
        CFBundleShortVersionString="1.0",
        CFBundleVersion="1",
        LSMinimumSystemVersion="$(MACOSX_DEPLOYMENT_TARGET)",
        NSHumanReadableCopyright="",
        NSMainStoryboardFile="Main",
        NSPrincipalClass="NSApplication",
    )
    with open(d / "Info.plist", "wb") as f:
        plistlib.dump(plist, f)

    # Entitlements
    ents = {"com.apple.security.app-sandbox": True}
    with open(d / f"{APP_ID_SAFE}.entitlements", "wb") as f:
        plistlib.dump(ents, f)

    # Minimal storyboard
    lproj = d / "Base.lproj"
    lproj.mkdir(exist_ok=True)
    (lproj / "Main.storyboard").write_text("""\
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.Cocoa.Storyboard.XIB" version="3.0"
          toolsVersion="21701" targetRuntime="MacOSX.cocoa"
          propertyAccessControl="none" useAutolayout="YES"
          customObjectInstantiationMethod="direct">
    <dependencies><deployment identifier="macosx"/></dependencies>
    <scenes>
        <scene sceneID="KUk-hi-LPx">
            <objects>
                <application id="hnI-AP-oxe" sceneMemberID="applicationObject">
                    <connections>
                        <outlet property="delegate" destination="Voe-Tx-rLC" id="GzC-gU-4Tm"/>
                    </connections>
                </application>
                <customObject id="Voe-Tx-rLC" customClass="AppDelegate" customModule="SafariSwipe"
                              customModuleProvider="target" sceneMemberID="delegate"/>
                <customObject id="YLy-65-1bz" customClass="NSFontManager" sceneMemberID="fontManager"/>
                <menu title="Main Menu" systemMenu="main" id="AV2-I0-qfu">
                    <items>
                        <menuItem title="Safari Swipe" id="1Xt-HY-uBw">
                            <menu title="Safari Swipe" systemMenu="apple" id="uQy-DD-JDr">
                                <items>
                                    <menuItem title="Quit Safari Swipe" keyEquivalent="q" id="4sb-4s-VLi">
                                        <connections><action selector="terminate:" target="Xt5-WX-oUL" id="Te7-pn-YzF"/></connections>
                                    </menuItem>
                                </items>
                            </menu>
                        </menuItem>
                    </items>
                </menu>
            </objects>
        </scene>
        <scene sceneID="hIz-AP-VOD">
            <objects>
                <window title="Safari Swipe" allowsToolTipsWhenApplicationIsInactive="NO"
                        autorecalculatesKeyViewLoop="NO" releasedWhenClosed="NO"
                        animationBehavior="default" id="QvC-M9-y7g" sceneMemberID="viewController">
                    <windowStyleMask key="styleMask" titled="YES" closable="YES" miniaturizable="YES" resizable="YES"/>
                    <rect key="contentRect" x="196" y="240" width="480" height="270"/>
                    <windowPositionMask key="initialPositionMask" leftStrut="YES" bottomStrut="YES"/>
                    <view key="contentView" wantsLayer="YES" id="EiT-Mj-1SZ">
                        <rect key="frame" x="0.0" y="0.0" width="480" height="270"/>
                        <autoresizingMask key="autoresizingMask"/>
                        <subviews>
                            <button verticalHuggingPriority="750" id="KOo-zK-BGd">
                                <rect key="frame" x="168" y="116" width="144" height="32"/>
                                <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMinY="YES"/>
                                <buttonCell key="cell" type="push" title="Open Extension Preferences"
                                            bezelStyle="rounded" alignment="center" borderStyle="border"
                                            imageScaling="proportionallyDown" inset="2" id="CO3-t8-eCu">
                                    <behavior key="behavior" pushIn="YES" lightByBackground="YES" lightByGray="YES"/>
                                    <font key="font" metaFont="system"/>
                                </buttonCell>
                                <connections>
                                    <action selector="openExtensionPrefs:" target="-2" id="Y6b-OD-oYU"/>
                                </connections>
                            </button>
                        </subviews>
                    </view>
                    <point key="canvasLocation" x="75" y="245"/>
                </window>
                <customObject id="-2" userLabel="File's Owner" customClass="ViewController"
                              customModule="SafariSwipe" customModuleProvider="target" sceneMemberID="menus"/>
            </objects>
        </scene>
    </scenes>
</document>
""")

    # Assets catalog
    assets = d / "Assets.xcassets"
    assets.mkdir(exist_ok=True)
    (assets / "Contents.json").write_text('{"info":{"author":"xcode","version":1}}')
    appicon = assets / "AppIcon.appiconset"
    appicon.mkdir(exist_ok=True)
    (appicon / "Contents.json").write_text('{"images":[],"info":{"author":"xcode","version":1}}')

    for name in [d / "AppDelegate.swift", d / "ViewController.swift"]:
        print(f"  {name}")

def write_ext_sources():
    d = PROJ_DIR / f"{APP_NAME} Extension"
    d.mkdir(parents=True, exist_ok=True)

    (d / "SafariWebExtensionHandler.swift").write_text("""\
import SafariServices
import os.log

let SFExtensionMessageKey = "message"

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems[0] as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey]
        os_log(.default, "Safari Swipe received message from browser.runtime.sendNativeMessage: %@", message as! CVarArg)
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["Response": "Received"]]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
""")

    plist = dict(
        CFBundleDevelopmentRegion="$(DEVELOPMENT_LANGUAGE)",
        CFBundleDisplayName="Safari Swipe",
        CFBundleExecutable="$(EXECUTABLE_NAME)",
        CFBundleIdentifier="$(PRODUCT_BUNDLE_IDENTIFIER)",
        CFBundleInfoDictionaryVersion="6.0",
        CFBundleName="$(PRODUCT_NAME)",
        CFBundlePackageType="$(PRODUCT_BUNDLE_PACKAGE_TYPE)",
        CFBundleShortVersionString="1.0",
        CFBundleVersion="1",
        LSMinimumSystemVersion="$(MACOSX_DEPLOYMENT_TARGET)",
        NSExtension=dict(
            NSExtensionPointIdentifier="com.apple.Safari.web-extension",
            NSExtensionPrincipalClass="$(PRODUCT_MODULE_NAME).SafariWebExtensionHandler",
        ),
    )
    with open(d / "Info.plist", "wb") as f:
        plistlib.dump(plist, f)

    ents = {
        "com.apple.security.app-sandbox": True,
        "com.apple.developer.web-browser-engine.webcontent": False,
    }
    with open(d / f"{APP_ID_SAFE}Extension.entitlements", "wb") as f:
        plistlib.dump(ents, f)

    # Copy web extension resources
    res = d / "Resources"
    res.mkdir(exist_ok=True)
    images = res / "images"
    images.mkdir(exist_ok=True)

    for fname in ["manifest.json", "background.js", "content.js"]:
        shutil.copy2(EXT_SRC / fname, res / fname)
        print(f"  {res / fname}")

    for fname in ["icon-48.png", "icon-96.png", "icon-128.png", "icon-256.png"]:
        shutil.copy2(EXT_SRC / "images" / fname, images / fname)
        print(f"  {images / fname}")

if __name__ == "__main__":
    print(f"Generating Xcode project in {PROJ_DIR}/ ...")
    PROJ_DIR.mkdir(exist_ok=True)
    write_project()
    write_app_sources()
    write_ext_sources()
    print(f"\nDone! Open SafariSwipe/SafariSwipe.xcodeproj in Xcode.")
    print("Then: Product > Run, then enable the extension in Safari > Settings > Extensions.")
