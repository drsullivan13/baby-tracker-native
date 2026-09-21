#!/usr/bin/env python3
"""Generate the dependency-free BabyTracker.xcodeproj deterministically."""

from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT / "BabyTracker.xcodeproj"

domain = sorted((ROOT / "Sources/BabyTrackerDomain").glob("*.swift"))
persistence = sorted((ROOT / "Sources/BabyTrackerPersistence").glob("*.swift"))
app = sorted((ROOT / "Sources/BabyTrackerApp").glob("*.swift"))
ui_tests = sorted((ROOT / "Tests/BabyTrackerUITests").glob("*.swift"))
tests = sorted((ROOT / "Tests/BabyTrackerDomainTests").glob("*.swift"))


def uid(label: str) -> str:
    return hashlib.sha1(label.encode()).hexdigest()[:24].upper()


objects = {}


def add(label: str, text: str) -> str:
    key = uid(label)
    objects[key] = text
    return key


def ref(path: Path, file_type: str = "sourcecode.swift") -> str:
    relative = path.relative_to(ROOT).as_posix()
    return add(f"ref:{relative}", f"isa = PBXFileReference; lastKnownFileType = {file_type}; path = {quote(relative)}; sourceTree = SOURCE_ROOT;")


def quote(value: str) -> str:
    return '"' + value.replace('"', '\\"') + '"'


def source_phase(label: str, refs: list[str]) -> str:
    builds = [
        add(f"build:{label}:{reference}", f"isa = PBXBuildFile; fileRef = {reference};")
        for reference in refs
    ]
    return add(f"phase:{label}", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({','.join(builds)}); runOnlyForDeploymentPostprocessing = 0;")


def framework_ref(name: str) -> str:
    return add(f"product:{name}", f"isa = PBXFileReference; explicitFileType = wrapper.framework; includeInIndex = 0; path = {quote(name)}; sourceTree = BUILT_PRODUCTS_DIR;")


def config(label: str, settings: dict[str, str]) -> str:
    body = " ".join(f"{key} = {value};" for key, value in settings.items())
    return add(f"config:{label}", f"isa = XCBuildConfiguration; buildSettings = {{ {body} }}; name = {label.split(':')[-1]};")


def config_list(label: str, settings: dict[str, str]) -> str:
    debug = config(f"{label}:Debug", settings | {"SWIFT_OPTIMIZATION_LEVEL": quote("-Onone"), "DEBUG_INFORMATION_FORMAT": "dwarf", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": quote("DEBUG")})
    release = config(f"{label}:Release", settings | {"SWIFT_COMPILATION_MODE": "wholemodule", "DEBUG_INFORMATION_FORMAT": quote("dwarf-with-dsym")})
    return add(f"configs:{label}", f"isa = XCConfigurationList; buildConfigurations = ({debug},{release}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")


common = {
    "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": "5.0",
    "CLANG_ENABLE_MODULES": "YES",
    "CODE_SIGN_STYLE": "Automatic",
    "DEVELOPMENT_TEAM": "68WZL8DZXC",
    "GENERATE_INFOPLIST_FILE": "YES",
    "DYLIB_INSTALL_NAME_BASE": quote("@rpath"),
    "LD_RUNPATH_SEARCH_PATHS": quote("$(inherited) @executable_path/Frameworks @loader_path/Frameworks"),
}

domain_refs = [ref(path) for path in domain]
persistence_refs = [ref(path) for path in persistence]
app_refs = [ref(path) for path in app]
test_refs = [ref(path) for path in tests]
ui_refs = [ref(path) for path in ui_tests]
plist_ref = ref(ROOT / "Info.plist", "text.plist.xml")

domain_product = framework_ref("BabyTrackerDomain.framework")
persistence_product = framework_ref("BabyTrackerPersistence.framework")
app_product = add("product:app", "isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = \"Baby Tracker.app\"; sourceTree = BUILT_PRODUCTS_DIR;")
test_product = add("product:tests", "isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = BabyTrackerTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;")

resource_refs = [ref(ROOT / "Assets.xcassets", "folder.assetcatalog"), ref(ROOT / "PrivacyInfo.xcprivacy", "text.xml")]
resource_builds = [add(f"resource:{reference}", f"isa = PBXBuildFile; fileRef = {reference};") for reference in resource_refs]
empty_resources = add("phase:resources", f"isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({','.join(resource_builds)}); runOnlyForDeploymentPostprocessing = 0;")
empty_frameworks_domain = add("phase:frameworks:domain", "isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;")


def dependency(label: str, target: str) -> str:
    proxy = add(f"proxy:{label}", f"isa = PBXContainerItemProxy; containerPortal = {uid('project')}; proxyType = 1; remoteGlobalIDString = {target}; remoteInfo = {quote(label)};")
    return add(f"dependency:{label}", f"isa = PBXTargetDependency; target = {target}; targetProxy = {proxy};")


domain_target = uid("target:domain")
persistence_target = uid("target:persistence")
app_target = uid("target:app")
test_target = uid("target:tests")
ui_target = uid("target:uitests")

domain_phase = source_phase("domain", domain_refs)
persistence_phase = source_phase("persistence", persistence_refs)
app_phase = source_phase("app", app_refs)
test_phase = source_phase("tests", test_refs)

domain_link = add("link:domain:persistence", f"isa = PBXBuildFile; fileRef = {domain_product};")
persistence_frameworks = add("phase:frameworks:persistence", f"isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({domain_link}); runOnlyForDeploymentPostprocessing = 0;")
domain_link_app = add("link:domain:app", f"isa = PBXBuildFile; fileRef = {domain_product};")
persistence_link_app = add("link:persistence:app", f"isa = PBXBuildFile; fileRef = {persistence_product};")
app_frameworks = add("phase:frameworks:app", f"isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({domain_link_app},{persistence_link_app}); runOnlyForDeploymentPostprocessing = 0;")
domain_link_tests = add("link:domain:tests", f"isa = PBXBuildFile; fileRef = {domain_product};")
persistence_link_tests = add("link:persistence:tests", f"isa = PBXBuildFile; fileRef = {persistence_product};")
test_frameworks = add("phase:frameworks:tests", f"isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({domain_link_tests},{persistence_link_tests}); runOnlyForDeploymentPostprocessing = 0;")

embed_refs = [add(f"embed:{name}", f"isa = PBXBuildFile; fileRef = {product}; settings = {{ ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy); }};") for name, product in [("domain", domain_product), ("persistence", persistence_product)]]
embed_phase = add("phase:embed", f"isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = \"\"; dstSubfolderSpec = 10; files = ({','.join(embed_refs)}); name = \"Embed Frameworks\"; runOnlyForDeploymentPostprocessing = 0;")

domain_configs = config_list("domain", common | {"PRODUCT_BUNDLE_IDENTIFIER": "com.dansullivan.babytracker.domain", "PRODUCT_NAME": "BabyTrackerDomain", "DEFINES_MODULE": "YES", "SKIP_INSTALL": "YES"})
persistence_configs = config_list("persistence", common | {"PRODUCT_BUNDLE_IDENTIFIER": "com.dansullivan.babytracker.persistence", "PRODUCT_NAME": "BabyTrackerPersistence", "DEFINES_MODULE": "YES", "SKIP_INSTALL": "YES"})
app_configs = config_list("app", common | {
    "PRODUCT_BUNDLE_IDENTIFIER": "com.dansullivan.babytracker",
    "PRODUCT_NAME": quote("Baby Tracker"),
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "INFOPLIST_FILE": "Info.plist",
    "GENERATE_INFOPLIST_FILE": "NO",
    "TARGETED_DEVICE_FAMILY": quote("1"),

})
test_configs = config_list("tests", common | {"PRODUCT_BUNDLE_IDENTIFIER": "com.dansullivan.babytracker.tests", "PRODUCT_NAME": "BabyTrackerTests", "GENERATE_INFOPLIST_FILE": "YES", "SKIP_INSTALL": "YES"})

objects[domain_target] = f"isa = PBXNativeTarget; buildConfigurationList = {domain_configs}; buildPhases = ({domain_phase},{empty_frameworks_domain}); buildRules = (); dependencies = (); name = BabyTrackerDomain; productName = BabyTrackerDomain; productReference = {domain_product}; productType = \"com.apple.product-type.framework\";"
objects[persistence_target] = f"isa = PBXNativeTarget; buildConfigurationList = {persistence_configs}; buildPhases = ({persistence_phase},{persistence_frameworks}); buildRules = (); dependencies = ({dependency('domain-persistence', domain_target)}); name = BabyTrackerPersistence; productName = BabyTrackerPersistence; productReference = {persistence_product}; productType = \"com.apple.product-type.framework\";"
objects[app_target] = f"isa = PBXNativeTarget; buildConfigurationList = {app_configs}; buildPhases = ({app_phase},{app_frameworks},{empty_resources},{embed_phase}); buildRules = (); dependencies = ({dependency('domain-app', domain_target)},{dependency('persistence-app', persistence_target)}); name = \"Baby Tracker\"; productName = \"Baby Tracker\"; productReference = {app_product}; productType = \"com.apple.product-type.application\";"
objects[test_target] = f"isa = PBXNativeTarget; buildConfigurationList = {test_configs}; buildPhases = ({test_phase},{test_frameworks}); buildRules = (); dependencies = ({dependency('domain-tests', domain_target)},{dependency('persistence-tests', persistence_target)}); name = BabyTrackerTests; productName = BabyTrackerTests; productReference = {test_product}; productType = \"com.apple.product-type.bundle.unit-test\";"

ui_product = add("product:uitests", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = BabyTrackerUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
ui_phase = source_phase("uitests", ui_refs)
ui_configs = config_list("uitests", common | {"PRODUCT_BUNDLE_IDENTIFIER": "com.dansullivan.babytracker.uitests", "PRODUCT_NAME": "BabyTrackerUITests", "GENERATE_INFOPLIST_FILE": "YES", "TEST_TARGET_NAME": quote("Baby Tracker"), "TARGETED_DEVICE_FAMILY": quote("1"), "SKIP_INSTALL": "YES"})
objects[ui_target] = f'isa = PBXNativeTarget; buildConfigurationList = {ui_configs}; buildPhases = ({ui_phase}); buildRules = (); dependencies = ({dependency("app-uitests", app_target)}); name = BabyTrackerUITests; productName = BabyTrackerUITests; productReference = {ui_product}; productType = "com.apple.product-type.bundle.ui-testing";'

all_source_refs = domain_refs + persistence_refs + app_refs + test_refs + ui_refs + [plist_ref] + resource_refs
main_group = add("group:main", f"isa = PBXGroup; children = ({','.join(all_source_refs)},{uid('group:products')}); sourceTree = \"<group>\";")
objects[uid("group:products")] = f"isa = PBXGroup; children = ({app_product},{domain_product},{persistence_product},{test_product},{ui_product}); name = Products; sourceTree = \"<group>\";"

project_configs = config_list("project", {
    "SWIFT_VERSION": "5.0",
    "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
    "CLANG_ENABLE_MODULES": "YES",
})
project = uid("project")
objects[project] = f"""isa = PBXProject;
attributes = {{ BuildIndependentTargetsInParallel = YES; LastSwiftUpdateCheck = 1600; LastUpgradeCheck = 1600;
TargetAttributes = {{ {app_target} = {{ CreatedOnToolsVersion = 16.0; }}; }}; }};
buildConfigurationList = {project_configs};
compatibilityVersion = "Xcode 15.0";
developmentRegion = en;
hasScannedForEncodings = 0;
knownRegions = (en, Base);
mainGroup = {main_group};
productRefGroup = {uid('group:products')};
projectDirPath = "";
projectRoot = "";
targets = ({app_target},{domain_target},{persistence_target},{test_target},{ui_target});
"""

PROJECT.mkdir(exist_ok=True)
body = "\n".join(f"\t\t{key} = {{ {value} }};" for key, value in sorted(objects.items()))
(PROJECT / "project.pbxproj").write_text(
    "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 60;\n\tobjects = {\n"
    + body
    + f"\n\t}};\n\trootObject = {project};\n}}\n"
)
print(f"Generated {PROJECT.relative_to(ROOT)} with {len(objects)} objects")

from xml.etree.ElementTree import Element, SubElement, ElementTree
scheme = Element("Scheme", LastUpgradeVersion="2700", version="1.3")
def build_ref(parent, target, product, name):
    SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=target, BuildableName=product, BlueprintName=name, ReferencedContainer="container:BabyTracker.xcodeproj")
entries = SubElement(SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES"), "BuildActionEntries")
entry = SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="YES", buildForProfiling="YES", buildForArchiving="YES", buildForAnalyzing="YES")
build_ref(entry, app_target, "Baby Tracker.app", "Baby Tracker")
test_action = SubElement(scheme, "TestAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="YES")
testables = SubElement(test_action, "Testables")
for target, product, name in [(test_target,"BabyTrackerTests.xctest","BabyTrackerTests"),(ui_target,"BabyTrackerUITests.xctest","BabyTrackerUITests")]:
    build_ref(SubElement(testables, "TestableReference", skipped="NO", parallelizable="NO"), target, product, name)
launch = SubElement(scheme, "LaunchAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", launchStyle="0", useCustomWorkingDirectory="NO", ignoresPersistentStateOnLaunch="NO", debugDocumentVersioning="YES", debugServiceExtension="internal", allowLocationSimulation="YES")
build_ref(SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0"), app_target,"Baby Tracker.app","Baby Tracker")
SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
shared = PROJECT / "xcshareddata/xcschemes"
shared.mkdir(parents=True, exist_ok=True)
ElementTree(scheme).write(shared / "Baby Tracker.xcscheme", encoding="UTF-8", xml_declaration=True)
