require 'webgen/tag'
class PrevNextTag
    include Webgen::Tag::Base

    def call(tag, body, context)
        node = context.content_node
        while !node.is_file?
            node = node.parent
        end

        siblings = node.parent.children.sort
        siblings.delete_if { |n| !n.meta_info['in_menu'] }
        prev, _ = siblings.
            enum_for(:each_cons, 2).
            find { |prev, this| this == node }
        _, nxt = siblings.
            enum_for(:each_cons, 2).
            find { |this, nxt| this == node }

        content = if tag == "next" && nxt
                      node.link_to(nxt)
                  elsif tag == "previous" && prev
                      node.link_to(prev)
                  end

        if content
            if !body.empty?
                body.gsub '%', content
            else
                content
            end
        end
    end
end

config = Webgen::WebsiteAccess.website.config
config['contentprocessor.tags.map']['previous'] = 'PrevNextTag'
config['contentprocessor.tags.map']['next'] = 'PrevNextTag'


