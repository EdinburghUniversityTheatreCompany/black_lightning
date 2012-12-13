kramdown
========

Most text entered into the Bedlam Admin site will be rendered using kramdown.

kramdown is an increadibly powerful, yet very natrual markup language.

More details about kramdown can be found [here](http://kramdown.rubyforge.org/syntax.html#links-and-images).

You can view this file in raw kramdown format [here](kramdown.txt)

---------------------------------------------------------

Paragraphs
----------

Starting a new paragraph is easy. Simply create two newlines.

    This is some text.

    This is a new paragraph.

However, one of the few oddities of kramdown is that a single newline will not have any effect.

Fear not! You can force kramdown to create a newline by putting two spaces before the newline:

    This is some text.  
    This is on a newline.

---------------------------------------------------------

Links
-----

kramdown supports two style of links: *inline* and *reference*.  
Details about reference links can be found on the [kramdown website](http://kramdown.rubyforge.org/syntax.html#links-and-images)

Inline links can be created as follows:

    [This](http://xtspro.com/+/eutc/) is EUTC's XTSPro page.

If you're referring to a page that is on the Bedlam Website, you can use
relative paths:

    See the [About](/about/) page for details.

---------------------------------------------------------

Images
------

Images are very similar to links, simply use:

    ![Image description](/attachments/myimage)

---------------------------------------------------------

Headers
-------

Headers can be created by 'underlining' the text with dashes or equals signs.

    This is a major header
    ======================

    This is a minor header
    ----------------------

Styles
------

You can apply styles using Inline Attribute Lists.

    My paragraph to be centered.
    {:.center}

    ![Img](/my/image/to/float){:.float-right}

The following styles have been provided for use:

| `{:.center}`      | Centrally aligns content
| `{:.float-right}` | Causes the content to "float" to the right hand side, allowing other text to wrap around it.
| `{:.float-left}`  | Causes the content to "float" to the left hand side, allowing other text to wrap around it.