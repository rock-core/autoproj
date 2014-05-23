require 'test/unit'
require 'autoproj'

class TC_PackageManifest < Test::Unit::TestCase

    DATA_DIR = File.expand_path('data', File.dirname(__FILE__))

    FakePackage = Struct.new :name, :os_packages

    attr_reader :pkg

    def setup
        @pkg = FakePackage.new('test', [])
    end

    def test_complete_manifest
        data = File.join(DATA_DIR, 'full_manifest.xml')
        manifest = Autoproj::PackageManifest.load(pkg, data)

        assert_equal %w{tag1 tag2 tag3}, manifest.tags
        assert_equal "full_doc", manifest.documentation
        assert_equal "short_doc", manifest.short_documentation

        deps = [['dep1', false], ['dep2', false]]
        opt_deps = [['opt_dep1', true], ['opt_dep2', true]]
        osdeps = [['osdep1', false], ['osdep2', false]]
        pkg.os_packages << "osdep2"

        assert_equal(osdeps, manifest.each_os_dependency.to_a)
        assert_equal(deps + opt_deps, manifest.each_package_dependency.to_a)
        assert_equal((deps + opt_deps + osdeps).to_set, manifest.each_dependency.to_set)

        authors = [
            ["Author1", "author1@email"],
            ["Author2", "author2@email"],
            ["Author3", nil]]
        assert_equal(authors.to_set, manifest.each_author.to_set)

        assert_equal('the_url', manifest.url)
        assert_equal('BSD', manifest.license)
    end

    def test_empty_manifest
        data = File.join(DATA_DIR, 'empty_manifest.xml')
        manifest = Autoproj::PackageManifest.load(pkg, data)

        assert_equal [], manifest.tags
        assert(manifest.documentation =~ /no documentation available/)
        assert(manifest.short_documentation =~ /no documentation available/)

        assert(manifest.each_os_dependency.to_a.empty?)
        assert(manifest.each_package_dependency.to_a.empty?)
        assert(manifest.each_dependency.to_a.empty?)
        assert(manifest.each_author.to_a.empty?)

        assert_equal(nil, manifest.url)
        assert_equal(nil, manifest.license)
    end

    def test_failure_on_wrong_document
        data = File.join(DATA_DIR, 'invalid_manifest.xml')
        assert_raises(Autobuild::PackageException) { Autoproj::PackageManifest.load(pkg, data) }
    end
end

