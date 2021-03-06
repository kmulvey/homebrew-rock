require 'formula'

class RockRuntimeNode010 < Formula
  homepage 'http://nodejs.org/'
  url 'http://nodejs.org/dist/v0.10.24/node-v0.10.24.tar.gz'
  sha1 'd162d01eb173cb5a0e7e46c9d706421c4c771039'

  keg_only 'rock'

  # fixes gyp's detection of system paths on CLT-only systems
  def patches; DATA; end

  def install
    system './configure', "--prefix=#{prefix}"
    system 'make', 'install'

    (prefix + 'rock.yml').write <<-EOS.undent
      env:
        PATH: "#{bin}:${PATH}"
    EOS

    runtime = var + 'rock/opt/rock/runtime'
    runtime.mkpath
    runtime += 'node010'
    system 'rm', '-fr', runtime if runtime.exist?

    File.symlink(prefix, runtime)
  end
end

__END__
diff --git a/tools/gyp/pylib/gyp/xcode_emulation.py b/tools/gyp/pylib/gyp/xcode_emulation.py
index 520dcc4..531e755 100644
--- a/tools/gyp/pylib/gyp/xcode_emulation.py
+++ b/tools/gyp/pylib/gyp/xcode_emulation.py
@@ -280,7 +280,14 @@ class XcodeSettings(object):
     return out.rstrip('\n')
 
   def _GetSdkVersionInfoItem(self, sdk, infoitem):
-    return self._GetStdout(['xcodebuild', '-version', '-sdk', sdk, infoitem])
+    # xcodebuild requires Xcode and can't run on Command Line Tools-only
+    # systems from 10.7 onward.
+    # Since the CLT has no SDK paths anyway, returning None is the
+    # most sensible route and should still do the right thing.
+    try:
+      return self._GetStdout(['xcodebuild', '-version', '-sdk', sdk, infoitem])
+    except:
+      pass
 
   def _SdkRoot(self, configname):
     if configname is None:
@@ -409,10 +416,11 @@ class XcodeSettings(object):
 
     cflags += self._Settings().get('WARNING_CFLAGS', [])
 
-    config = self.spec['configurations'][self.configname]
-    framework_dirs = config.get('mac_framework_dirs', [])
-    for directory in framework_dirs:
-      cflags.append('-F' + directory.replace('$(SDKROOT)', sdk_root))
+    if 'SDKROOT' in self._Settings():
+      config = self.spec['configurations'][self.configname]
+      framework_dirs = config.get('mac_framework_dirs', [])
+      for directory in framework_dirs:
+        cflags.append('-F' + directory.replace('$(SDKROOT)', sdk_root))
 
     self.configname = None
     return cflags
@@ -659,10 +667,11 @@ class XcodeSettings(object):
     for rpath in self._Settings().get('LD_RUNPATH_SEARCH_PATHS', []):
       ldflags.append('-Wl,-rpath,' + rpath)
 
-    config = self.spec['configurations'][self.configname]
-    framework_dirs = config.get('mac_framework_dirs', [])
-    for directory in framework_dirs:
-      ldflags.append('-F' + directory.replace('$(SDKROOT)', self._SdkPath()))
+    if 'SDKROOT' in self._Settings():
+      config = self.spec['configurations'][self.configname]
+      framework_dirs = config.get('mac_framework_dirs', [])
+      for directory in framework_dirs:
+        ldflags.append('-F' + directory.replace('$(SDKROOT)', self._SdkPath()))
 
     self.configname = None
     return ldflags
@@ -843,7 +852,10 @@ class XcodeSettings(object):
         l = '-l' + m.group(1)
       else:
         l = library
-    return l.replace('$(SDKROOT)', self._SdkPath(config_name))
+    if self._SdkPath():
+      return l.replace('$(SDKROOT)', self._SdkPath(config_name))
+    else:
+      return l
 
   def AdjustLibraries(self, libraries, config_name=None):
     """Transforms entries like 'Cocoa.framework' in libraries into entries like
@@ -856,6 +868,27 @@ class XcodeSettings(object):
   def _BuildMachineOSBuild(self):
     return self._GetStdout(['sw_vers', '-buildVersion'])
 
+  # This method ported from the logic in Homebrew's CLT version check
+  def _CLTVersion(self):
+    # pkgutil output looks like
+    #   package-id: com.apple.pkg.CLTools_Executables
+    #   version: 5.0.1.0.1.1382131676
+    #   volume: /
+    #   location: /
+    #   install-time: 1382544035
+    #   groups: com.apple.FindSystemFiles.pkg-group com.apple.DevToolsBoth.pkg-group com.apple.DevToolsNonRelocatableShared.pkg-group
+    STANDALONE_PKG_ID = "com.apple.pkg.DeveloperToolsCLILeo"
+    FROM_XCODE_PKG_ID = "com.apple.pkg.DeveloperToolsCLI"
+    MAVERICKS_PKG_ID = "com.apple.pkg.CLTools_Executables"
+
+    regex = re.compile('version: (?P<version>.+)')
+    for key in [MAVERICKS_PKG_ID, STANDALONE_PKG_ID, FROM_XCODE_PKG_ID]:
+      try:
+        output = self._GetStdout(['/usr/sbin/pkgutil', '--pkg-info', key])
+        return re.search(regex, output).groupdict()['version']
+      except:
+        continue
+
   def _XcodeVersion(self):
     # `xcodebuild -version` output looks like
     #    Xcode 4.6.3
@@ -866,13 +899,30 @@ class XcodeSettings(object):
     #    BuildVersion: 10M2518
     # Convert that to '0463', '4H1503'.
     if len(XcodeSettings._xcode_version_cache) == 0:
-      version_list = self._GetStdout(['xcodebuild', '-version']).splitlines()
+      try:
+        version_list = self._GetStdout(['xcodebuild', '-version']).splitlines()
+        # In some circumstances xcodebuild exits 0 but doesn't return
+        # the right results; for example, a user on 10.7 or 10.8 with
+        # a bogus path set via xcode-select
+        # In that case this may be a CLT-only install so fall back to
+        # checking that version.
+        if len(version_list) < 2:
+          raise GypError, "xcodebuild returned unexpected results"
+      except:
+        version = self._CLTVersion()
+        if version:
+          version = re.match('(\d\.\d\.?\d*)', version).groups()[0]
+        else:
+          raise GypError, "No Xcode or CLT version detected!"
+        # The CLT has no build information, so we return an empty string.
+        version_list = [version, '']
       version = version_list[0]
       build = version_list[-1]
       # Be careful to convert "4.2" to "0420":
       version = version.split()[-1].replace('.', '')
       version = (version + '0' * (3 - len(version))).zfill(4)
-      build = build.split()[-1]
+      if build:
+        build = build.split()[-1]
       XcodeSettings._xcode_version_cache = (version, build)
     return XcodeSettings._xcode_version_cache
 
@@ -930,7 +980,11 @@ class XcodeSettings(object):
     default_sdk_root = XcodeSettings._sdk_root_cache.get(default_sdk_path)
     if default_sdk_root:
       return default_sdk_root
-    all_sdks = self._GetStdout(['xcodebuild', '-showsdks'])
+    try:
+      all_sdks = self._GetStdout(['xcodebuild', '-showsdks'])
+    except:
+      # If xcodebuild fails, there will be no valid SDKs
+      return ''
     for line in all_sdks.splitlines():
       items = line.split()
       if len(items) >= 3 and items[-2] == '-sdk':
