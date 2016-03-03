module Autoproj
        # Class holding information about which packages have been selected, and
        # why. It is used to decide whether some non-availability of packages
        # are errors or simply warnings (i.e. if the user really wants a given
        # package, or merely might be adding it by accident)
        class PackageSelection
            include Enumerable

            # The set of matches, i.e. a mapping from a user-provided string to
            # the set of packages it selected
            attr_reader :matches
            # The set of selected packages, as a hash of the package name to the
            # set of user-provided strings that caused that package to be
            # selected
            attr_reader :selection
            # A flag that tells #filter_excluded_and_ignored_packages whether
            # the a given package selection is weak or not.
            #
            # If true, a selection that have some excluded packages will not
            # generate an error. Otherwise (the default), an error is generated
            attr_reader :weak_dependencies
            # After a call to #filter_excluded_and_ignored_packages, this
            # contains the set of package exclusions that have been ignored
            # because the corresponding metapackage has a weak dependency policy
            attr_reader :exclusions
            # After a call to #filter_excluded_and_ignored_packages, this
            # contains the set of package ignores that have been ignored because
            # the corresponding metapackage has a weak dependency policy
            attr_reader :ignores
            # The set of source packages that have been selected
            attr_reader :source_packages
            # The set of osdeps that have been selected
            attr_reader :osdeps

            def initialize
                @selection = Hash.new { |h, k| h[k] = Set.new }
                @matches = Hash.new { |h, k| h[k] = Set.new }
                @weak_dependencies = Hash.new
                @ignores = Hash.new { |h, k| h[k] = Set.new }
                @exclusions = Hash.new { |h, k| h[k] = Set.new }
                @source_packages = Set.new
                @osdeps = Set.new
            end

            def include?(pkg_name)
                selection.has_key?(pkg_name)
            end

            def empty?
                selection.empty?
            end

            def each(&block)
                Autoproj.warn_deprecated "PackageSelection#each", "use PackageSelection#each_source_package_name instead", 0
                each_source_package_name(&block)
            end

            def each_source_package_name(&block)
                source_packages.each(&block)
            end

            def each_osdep_package_name(&block)
                osdeps.each(&block)
            end

            def packages
                Autoproj.warn_deprecated "PackageSelection#packages", "use PackageSelection#source_packages instead", 0
                source_packages
            end

            def select(sel, packages, options = Hash.new)
                if !options.kind_of?(Hash)
                    Autoproj.warn_deprecated "calling PackageSelection#select with a boolean as third argument", "use e.g. weak: true instead", 0
                    options = Hash[weak: options]
                end
                options = Kernel.validate_options options,
                    weak: false,
                    osdep: false

                packages = Array(packages).to_set
                matches[sel].merge(packages)
                packages.each do |pkg_name|
                    selection[pkg_name] << sel
                end
                if options[:osdep]
                    osdeps.merge(packages)
                else
                    source_packages.merge(packages)
                end

                weak_dependencies[sel] = options[:weak]
            end

            def initialize_copy(old)
                old.selection.each do |pkg_name, set|
                    @selection[pkg_name] = set.dup
                end
                old.matches.each do |sel, set|
                    @matches[sel] = set.dup
                end
                @source_packages = old.source_packages.dup
                @osdeps = old.osdeps.dup
            end

            def has_match_for?(sel)
                matches.has_key?(sel)
            end

            # Remove packages that are explicitely excluded and/or ignored
            #
            # Raise an error if an explicit selection expands only to an
            # excluded package, and display a warning for ignored packages
            def filter_excluded_and_ignored_packages(manifest)
                matches.each do |sel, expansion|
                    excluded, other = expansion.partition { |pkg_name| manifest.excluded?(pkg_name) }
                    ignored,  ok    = other.partition { |pkg_name| manifest.ignored?(pkg_name) }

                    if !excluded.empty? && (!weak_dependencies[sel] || (ok.empty? && ignored.empty?))
                        exclusions = excluded.map do |pkg_name|
                            [pkg_name, manifest.exclusion_reason(pkg_name)]
                        end
                        base_msg = "#{sel} is selected in the manifest or on the command line"
                        if exclusions.size == 1
                            reason = exclusions[0][1]
                            if sel == exclusions[0][0]
                                raise ExcludedSelection.new(sel), "#{base_msg}, but it is excluded from the build: #{reason}"
                            elsif weak_dependencies[sel]
                                raise ExcludedSelection.new(sel), "#{base_msg}, but it expands to #{exclusions.map(&:first).join(", ")}, which is excluded from the build: #{reason}"
                            else
                                raise ExcludedSelection.new(sel), "#{base_msg}, but its dependency #{exclusions.map(&:first).join(", ")} is excluded from the build: #{reason}"
                            end
                        elsif weak_dependencies[sel]
                            raise ExcludedSelection.new(sel), "#{base_msg}, but expands to #{exclusions.map(&:first).join(", ")}, and all these packages are excluded from the build:\n  #{exclusions.map { |name, reason| "#{name}: #{reason}" }.join("\n  ")}"
                        else
                            raise ExcludedSelection.new(sel), "#{base_msg}, but it requires #{exclusions.map(&:first).join(", ")}, and all these packages are excluded from the build:\n  #{exclusions.map { |name, reason| "#{name}: #{reason}" }.join("\n  ")}"
                        end
                    else
                        self.exclusions[sel] |= excluded.to_set.dup
                        self.ignores[sel] |= ignored.to_set.dup
                    end

                    excluded = excluded.to_set
                    ignored  = ignored.to_set
                    expansion.delete_if do |pkg_name|
                        ignored.include?(pkg_name) || excluded.include?(pkg_name)
                    end
                end

                source_packages.delete_if do |pkg_name| 
                    manifest.excluded?(pkg_name) || manifest.ignored?(pkg_name)
                end
                osdeps.delete_if do |pkg_name| 
                    manifest.excluded?(pkg_name) || manifest.ignored?(pkg_name)
                end
                selection.delete_if do |pkg_name, _|
                    manifest.excluded?(pkg_name) || manifest.ignored?(pkg_name)
                end
                matches.delete_if do |key, sel|
                    sel.empty?
                end
            end
        end
end

