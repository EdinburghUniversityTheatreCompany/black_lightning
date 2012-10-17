module NewsHelper

    # find the first line break after 140 characters
    def generate_preview (content)
        begin
            #FIXME: This pattern will only work if content ends in a newline.
            /.{,140}.+?<\/p>/m.match(content)[0]
        rescue Exception
            "There was an error rendering a preview for this news item."
        end
    end

end
