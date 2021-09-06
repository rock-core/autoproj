module Autoproj
    module PackageManagers
        class DebianVersion
            attr_reader :version
            attr_reader :epoch
            attr_reader :upstream_version
            attr_reader :debian_revision

            include Comparable

            def initialize(version)
                @version = version
                parse_version
            end

            def split
                [epoch, upstream_version, debian_revision]
            end

            def <=>(b)
                (0..2).inject(0) do |result, i|
                    return result unless result == 0
                    normalize(compare_fragments(split[i], b.split[i]))
                end
            end

            def self.compare(a, b)
                new(a) <=> new(b)
            end

            private

            def normalize(value)
                return -1 if value < 0
                return 1 if value > 0
                return 0 if value == 0
            end

            # Reference: https://www.debian.org/doc/debian-policy/ch-controlfields.html#version
            def parse_version
                @epoch = "0"
                @debian_revision = "0"

                @upstream_version = @version.split(":")
                if @upstream_version.size > 1
                    @epoch = @upstream_version.first
                    @upstream_version = @upstream_version[1..-1].join(":")
                else
                    @upstream_version = @upstream_version.first
                end

                @upstream_version = @upstream_version.split("-")
                if @upstream_version.size > 1
                    @debian_revision = @upstream_version.last
                    @upstream_version = @upstream_version[0..-2].join("-")
                else
                    @upstream_version = @upstream_version.first
                end
            end

            def alpha?(look_ahead)
                look_ahead =~ /[[:alpha:]]/
            end

            def digit?(look_ahead)
                look_ahead =~ /[[:digit:]]/
            end

            def order(c)
                if digit?(c)
                    0
                elsif alpha?(c)
                    c.ord
                elsif c == "~"
                    -1
                elsif c
                    c.ord + 256
                else
                    0
                end
            end

            # Ported from https://github.com/Debian/apt/blob/master/apt-pkg/deb/debversion.cc
            def compare_fragments(a, b)
                i = 0
                j = 0
                while i != a.size && j != b.size
                    first_diff = 0
                    while i != a.size && j != b.size && (!digit?(a[i]) || !digit?(b[j]))
                        vc = order(a[i])
                        rc = order(b[j])
                        return vc - rc if vc != rc
                        i += 1
                        j += 1
                    end

                    i += 1 while a[i] == "0"
                    j += 1 while b[j] == "0"
                    while digit?(a[i]) && digit?(b[j])
                        first_diff = a[i].ord - b[j].ord if first_diff == 0
                        i += 1
                        j += 1
                    end

                    return 1 if digit?(a[i])
                    return -1 if digit?(b[j])
                    return first_diff if first_diff != 0
                end

                return 0 if i == a.size && j == b.size

                if i == a.size
                    return 1 if b[j] == "~"
                    return -1
                end
                if j == b.size
                    return -1 if a[i] == "~"
                    1
                end
            end
        end
    end
end
