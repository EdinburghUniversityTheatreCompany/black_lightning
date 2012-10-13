module NewsHelper

    # find the first line break after 140 characters
    def generate_preview (content)
        #FIXME: This pattern will only work if content ends in a newline.
        content = content + "\n"
        /.{,140}.+\n/m.match(content)[0]
    end

end
