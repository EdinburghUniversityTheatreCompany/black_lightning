module NewsHelper

    def generate_preview (content)
       # find the first line break after 140 characters
       /.{,140}.+\n/m.match(content)[0]
    end

end
