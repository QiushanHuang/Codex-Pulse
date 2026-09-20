#!/usr/bin/env python3
"""Generate the small, dependency-free native Widget Extension Xcode project."""
from pathlib import Path
import plistlib

ROOT = Path(__file__).resolve().parent.parent
project = ROOT/'macos/CodexPulse.xcodeproj'
project.mkdir(exist_ok=True)
objects = {}


def obj(n, isa, **fields):
    key = f'{n:024X}'
    objects[key] = {'isa':isa, **fields}
    return key


shared = obj(1,'PBXFileReference',lastKnownFileType='sourcecode.swift',path='Shared.swift',sourceTree='<group>')
widget = obj(2,'PBXFileReference',lastKnownFileType='sourcecode.swift',path='Widget.swift',sourceTree='<group>')
product = obj(3,'PBXFileReference',explicitFileType='wrapper.app-extension',path='CodexPulseWidget.appex',sourceTree='BUILT_PRODUCTS_DIR',includeInIndex=0)
builds = [obj(4,'PBXBuildFile',fileRef=shared),obj(5,'PBXBuildFile',fileRef=widget)]
sources = obj(6,'PBXSourcesBuildPhase',buildActionMask=2147483647,files=builds,runOnlyForDeploymentPostprocessing=0)
frameworks = obj(7,'PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
resources = obj(8,'PBXResourcesBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
settings = {'PRODUCT_BUNDLE_IDENTIFIER':'local.qiushan.CodexPulse.Widget','PRODUCT_NAME':'$(TARGET_NAME)',
            'SDKROOT':'macosx','MACOSX_DEPLOYMENT_TARGET':'14.0','SWIFT_VERSION':'5.0','SKIP_INSTALL':'YES',
            'APPLICATION_EXTENSION_API_ONLY':'YES','ENABLE_APP_SANDBOX':'YES',
            'ALWAYS_SEARCH_USER_PATHS':'NO',
            'CODE_SIGN_ENTITLEMENTS':'Widget.entitlements','CODE_SIGN_IDENTITY':'-',
            'CODE_SIGN_STYLE':'Manual','INFOPLIST_FILE':'WidgetInfo.plist',
            'GENERATE_INFOPLIST_FILE':'NO','SWIFT_OPTIMIZATION_LEVEL':'-O',
            'LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/../Frameworks','@executable_path/../../../../Frameworks']}
configs = [obj(9,'XCBuildConfiguration',name='Debug',buildSettings={**settings,'SWIFT_OPTIMIZATION_LEVEL':'-Onone'}),obj(10,'XCBuildConfiguration',name='Release',buildSettings=settings)]
configlist = obj(11,'XCConfigurationList',buildConfigurations=configs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
target = obj(12,'PBXNativeTarget',name='CodexPulseWidget',productName='CodexPulseWidget',productType='com.apple.product-type.app-extension',productReference=product,
             buildConfigurationList=configlist,buildPhases=[sources,frameworks,resources],buildRules=[],dependencies=[])
products = obj(13,'PBXGroup',children=[product],name='Products',sourceTree='<group>')
main = obj(14,'PBXGroup',children=[shared,widget,products],sourceTree='<group>')
projconfigs = [obj(15,'XCBuildConfiguration',name='Debug',buildSettings={}),obj(16,'XCBuildConfiguration',name='Release',buildSettings={})]
projlist = obj(17,'XCConfigurationList',buildConfigurations=projconfigs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
root = obj(18,'PBXProject',attributes={'LastUpgradeCheck':'2660'},buildConfigurationList=projlist,compatibilityVersion='Xcode 14.0',
           developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','Base'],mainGroup=main,productRefGroup=products,projectDirPath='',projectRoot='',targets=[target])
with (project/'project.pbxproj').open('wb') as f:
    plistlib.dump({'archiveVersion':'1','classes':{},'objectVersion':'56','objects':objects,'rootObject':root},f)
print(project)
