require 'formula'

class RockRuntimeRuby19 < Formula
  homepage 'http://www.python.org/'
  url 'http://ftp.ruby-lang.org/pub/ruby/1.9/ruby-1.9.3-p484.tar.gz'
  sha1 '6ae80f424968b5ce661ee9b2bee1c21adc9ee67c'

  env :std
  keg_only 'rock'

  depends_on 'readline'
  depends_on 'gdbm'
  depends_on 'libyaml'
  depends_on 'openssl'
  depends_on 'curl-ca-bundle'

  resource 'bundler' do
    url "https://rubygems.org/gems/bundler-1.3.4.gem"
    sha1 'fba95c4d82d4fa287de6baea99ed31af8b8973dc'
  end

  def abi_version
    '1.9.1'
  end

  def install_bundler
    ENV['GEM_HOME'] = "#{lib}/ruby/gems/#{abi_version}"

    resource('bundler').stage { |r|
      system 'gem', 'install',
        '--config-file', 'nofile',
        '--force',
        '--ignore-dependencies',
        '--no-rdoc',
        '--no-ri',
        '--local',
        '--install-dir', "#{lib}/ruby/gems/#{abi_version}",
        "--bindir", bin,
        r.cached_download
    }

    system 'mv', "#{bin}/bundle", "#{bin}/rock-bundle"

    (bin + 'bundle').write <<-EOS.undent
      #!/usr/bin/env bash
      unset RUBYOPT
      exec rock-bundle "$@"
    EOS

    system 'chmod', '755', "#{bin}/bundle"
  end

  def install
    lib.mkpath

    system './configure',
      "--prefix=#{prefix}",
      '--enable-shared',
      "--with-opt-dir=#{Formula.factory('openssl').opt_prefix}",
      "--with-opt-dir=#{Formula.factory('readline').prefix}"
    system 'make'
    system 'make', 'install'

    ENV['PATH'] = "#{bin}:#{ENV['PATH']}"

    install_bundler

    (prefix + 'rock.yml').write <<-EOS.undent
      env:
        PATH: "#{bin}:${PATH}"
        RUBY_ABI: "#{abi_version}"
        RUBYOPT: "-I#{lib}/ruby/gems/#{abi_version}/gems/bundler-#{resource('bundler').version}/lib -rbundler/setup"
        SSL_CERT_FILE: "#{Formula.factory('curl-ca-bundle').prefix}/share/ca-bundle.crt"
    EOS

    runtime = var + 'rock/opt/rock/runtime'
    runtime.mkpath
    runtime += 'ruby19'
    system 'rm', '-fr', runtime if runtime.exist?

    File.symlink(prefix, runtime)
  end
end
