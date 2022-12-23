require 'test_helper'

class MdHelperTest < ActionView::TestCase
  setup do
    # I just took this from somewhere, it seemed reasonably complex so it's useful for testing.rail
    @markdown = "kramdown\n========\n\nMost text entered into the Bedlam Admin site will be rendered using kramdown.\n\nkramdown is an increadibly powerful, yet very natrual markup language.\n\nMore details about kramdown can be found [here](http://kramdown.rubyforge.org/syntax.html#links-and-images).\n\nYou can view this file in raw kramdown format [here](kramdown.txt)\n\n---------------------------------------------------------\n\nParagraphs\n----------\n\nStarting a new paragraph is easy. Simply create two newlines.\n\n    This is some text.\n\n    This is a new paragraph.\n\nHowever, one of the few oddities of kramdown is that a single newline will not have any effect.\n\nFear not! You can force kramdown to create a newline by putting two spaces before the newline:\n\n    This is some text.  \n    This is on a newline.\n\n---------------------------------------------------------\n\nLinks\n-----\n\nkramdown supports two style of links: *inline* and *reference*.  \nDetails about reference links can be found on the [kramdown website](http://kramdown.rubyforge.org/syntax.html#links-and-images)\n\nInline links can be created as follows:\n\n    [This](http://xtspro.com/+/eutc/) is EUTC's XTSPro page.\n\nIf you're referring to a page that is on the Bedlam Website, you can use\nrelative paths:\n\n    See the [About](/about/) page for details.\n\n---------------------------------------------------------\n\nImages\n------\n\nImages are very similar to links, simply use:\n\n    ![Image description](/attachments/myimage)\n\nSee the section below on styles for resizing images.\n\nCaptioned Images\n----------------\n\nN.B - This is a custom extension that does not exist in normal kramdown.\n{:.alert}\n\nCaptioned images can be created as follows:\n\n    {::captioned_image .float-left}\n    ![Image Description](/attachments/myimage)\n\n    This is a caption\n    {:/captioned_image}\n\n---------------------------------------------------------\n\nHeaders\n-------\n\nHeaders can be created by 'underlining' the text with dashes or equals signs.\n\n    This is a major header\n    ======================\n\n    This is a minor header\n    ----------------------\n\nStyles\n------\n\nYou can apply styles using Inline Attribute Lists.\n\n    My paragraph to be centered.\n    {:.center}\n\n    ![Img](/my/image/to/float){:.float-right}\n\nThe following styles have been provided for use:\n\n| `{:.center}`      | Centrally aligns content\n| `{:.float-right}` | Causes the content to \"float\" to the right hand side, allowing other text to wrap around it.\n| `{:.float-left}`  | Causes the content to \"float\" to the left hand side, allowing other text to wrap around it.\n| `{:.zoomable)`    | For use on images. Allows the user to click on the image to make it larger. (Note that this will not work in the kramdown preview.)\n\nYou can also use your own styles:\n\n    Style It!\n    {:style=\"color: red;\"}\n\nThe style attribute can be any valid CSS. This is particularly useful with\nimages:\n\n    ![My Image](/attachments/my_image){:style=\"width: 100px;\"}\n    ![My Image](/attachments/my_tall_image){:style=\"height: 100px;\"}\n    \nFurther Tests\n=============\n\n{::captioned_image .float-left}\n![Image Description](/attachments/myimage)\n\nThis is a caption\n{:/captioned_image}\nThis is something else? {:captioned_pineapple}"
  end
  test 'render markdown' do
    assert_equal '', render_markdown(nil)
    html = "<h1 id=\"kramdown\">kramdown</h1>\n\n<p>Most text entered into the Bedlam Admin site will be rendered using kramdown.</p>\n\n<p>kramdown is an increadibly powerful, yet very natrual markup language.</p>\n\n<p>More details about kramdown can be found <a href=\"http://kramdown.rubyforge.org/syntax.html#links-and-images\">here</a>.</p>\n\n<p>You can view this file in raw kramdown format <a href=\"kramdown.txt\">here</a></p>\n\n<hr />\n\n<h2 id=\"paragraphs\">Paragraphs</h2>\n\n<p>Starting a new paragraph is easy. Simply create two newlines.</p>\n\n<pre><code>This is some text.\n\nThis is a new paragraph.\n</code></pre>\n\n<p>However, one of the few oddities of kramdown is that a single newline will not have any effect.</p>\n\n<p>Fear not! You can force kramdown to create a newline by putting two spaces before the newline:</p>\n\n<pre><code>This is some text.  \nThis is on a newline.\n</code></pre>\n\n<hr />\n\n<h2 id=\"links\">Links</h2>\n\n<p>kramdown supports two style of links: <em>inline</em> and <em>reference</em>.<br />\nDetails about reference links can be found on the <a href=\"http://kramdown.rubyforge.org/syntax.html#links-and-images\">kramdown website</a></p>\n\n<p>Inline links can be created as follows:</p>\n\n<pre><code>[This](http://xtspro.com/+/eutc/) is EUTC's XTSPro page.\n</code></pre>\n\n<p>If you’re referring to a page that is on the Bedlam Website, you can use\nrelative paths:</p>\n\n<pre><code>See the [About](/about/) page for details.\n</code></pre>\n\n<hr />\n\n<h2 id=\"images\">Images</h2>\n\n<p>Images are very similar to links, simply use:</p>\n\n<pre><code>![Image description](/attachments/myimage)\n</code></pre>\n\n<p>See the section below on styles for resizing images.</p>\n\n<h2 id=\"captioned-images\">Captioned Images</h2>\n\n<p class=\"alert\">N.B - This is a custom extension that does not exist in normal kramdown.</p>\n\n<p>Captioned images can be created as follows:</p>\n\n<pre><code>{::captioned_image .float-left}\n![Image Description](/attachments/myimage)\n\nThis is a caption\n{:/captioned_image}\n</code></pre>\n\n<hr />\n\n<h2 id=\"headers\">Headers</h2>\n\n<p>Headers can be created by ‘underlining’ the text with dashes or equals signs.</p>\n\n<pre><code>This is a major header\n======================\n\nThis is a minor header\n----------------------\n</code></pre>\n\n<h2 id=\"styles\">Styles</h2>\n\n<p>You can apply styles using Inline Attribute Lists.</p>\n\n<pre><code>My paragraph to be centered.\n{:.center}\n\n![Img](/my/image/to/float){:.float-right}\n</code></pre>\n\n<p>The following styles have been provided for use:</p>\n\n<table>\n  <tbody>\n    <tr>\n      <td><code>{:.center}</code></td>\n      <td>Centrally aligns content</td>\n    </tr>\n    <tr>\n      <td><code>{:.float-right}</code></td>\n      <td>Causes the content to “float” to the right hand side, allowing other text to wrap around it.</td>\n    </tr>\n    <tr>\n      <td><code>{:.float-left}</code></td>\n      <td>Causes the content to “float” to the left hand side, allowing other text to wrap around it.</td>\n    </tr>\n    <tr>\n      <td><code>{:.zoomable)</code></td>\n      <td>For use on images. Allows the user to click on the image to make it larger. (Note that this will not work in the kramdown preview.)</td>\n    </tr>\n  </tbody>\n</table>\n\n<p>You can also use your own styles:</p>\n\n<pre><code>Style It!\n{:style=\"color: red;\"}\n</code></pre>\n\n<p>The style attribute can be any valid CSS. This is particularly useful with\nimages:</p>\n\n<pre><code>![My Image](/attachments/my_image){:style=\"width: 100px;\"}\n![My Image](/attachments/my_tall_image){:style=\"height: 100px;\"}\n</code></pre>\n\n<h1 id=\"further-tests\">Further Tests</h1>\n\n<div class=\"captioned-image img-thumbnail float-left\">    <p><img src=\"/attachments/myimage\" alt=\"Image Description\" /></p>\n\n    <p>This is a caption</p>\n</div>\n<p>This is something else? {:captioned_pineapple}</p>\n"
    assert_equal html, render_markdown(@markdown)
  end

  test 'render plain' do
    assert_equal '', render_plain(nil)
    plain = "kramdown\n\nMost text entered into the Bedlam Admin site will be rendered using kramdown.\n\nkramdown is an increadibly powerful, yet very natrual markup language.\n\nMore details about kramdown can be found here.\n\nYou can view this file in raw kramdown format here\n\n\n\nParagraphs\n\nStarting a new paragraph is easy. Simply create two newlines.\n\nThis is some text.\n\nThis is a new paragraph.\n\n\nHowever, one of the few oddities of kramdown is that a single newline will not have any effect.\n\nFear not! You can force kramdown to create a newline by putting two spaces before the newline:\n\nThis is some text.  \nThis is on a newline.\n\n\n\n\nLinks\n\nkramdown supports two style of links: inline and reference.\nDetails about reference links can be found on the kramdown website\n\nInline links can be created as follows:\n\n[This](http://xtspro.com/+/eutc/) is EUTC's XTSPro page.\n\n\nIf you’re referring to a page that is on the Bedlam Website, you can use\nrelative paths:\n\nSee the [About](/about/) page for details.\n\n\n\n\nImages\n\nImages are very similar to links, simply use:\n\n![Image description](/attachments/myimage)\n\n\nSee the section below on styles for resizing images.\n\nCaptioned Images\n\nN.B - This is a custom extension that does not exist in normal kramdown.\n\nCaptioned images can be created as follows:\n\n{::captioned_image .float-left}\n![Image Description](/attachments/myimage)\n\nThis is a caption\n{:/captioned_image}\n\n\n\n\nHeaders\n\nHeaders can be created by ‘underlining’ the text with dashes or equals signs.\n\nThis is a major header\n======================\n\nThis is a minor header\n----------------------\n\n\nStyles\n\nYou can apply styles using Inline Attribute Lists.\n\nMy paragraph to be centered.\n{:.center}\n\n![Img](/my/image/to/float){:.float-right}\n\n\nThe following styles have been provided for use:\n\n\n  \n    \n      {:.center}\n      Centrally aligns content\n    \n    \n      {:.float-right}\n      Causes the content to “float” to the right hand side, allowing other text to wrap around it.\n    \n    \n      {:.float-left}\n      Causes the content to “float” to the left hand side, allowing other text to wrap around it.\n    \n    \n      {:.zoomable)\n      For use on images. Allows the user to click on the image to make it larger. (Note that this will not work in the kramdown preview.)\n    \n  \n\n\nYou can also use your own styles:\n\nStyle It!\n{:style=\"color: red;\"}\n\n\nThe style attribute can be any valid CSS. This is particularly useful with\nimages:\n\n![My Image](/attachments/my_image){:style=\"width: 100px;\"}\n![My Image](/attachments/my_tall_image){:style=\"height: 100px;\"}\n\n\nFurther Tests\n\n    \n\n    This is a caption\n\nThis is something else? {:captioned_pineapple}\n"
    assert_equal plain, render_plain(@markdown)
  end

  test 'truncated markdown' do
    archive_warning = '<i class="icon-info-sign icon-large"></i> This show was imported from the old website. If you are able to provide any more information, please contact the [Archivist](mailto:archive@bedlamtheatre.co.uk).
    {:.alert .alert-info}'
    expected_truncated_description = 'This show was imported from the old website. If you are a...'

    assert_equal expected_truncated_description, truncate_markdown(archive_warning, 60)

    description_with_comment = '<!-- it happened 2 years before 1980, idk when exactly -->Pineapple'

    assert_equal 'Pineapple', truncate_markdown(description_with_comment)
  end
end
