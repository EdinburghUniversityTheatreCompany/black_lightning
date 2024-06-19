// A fun easter egg when you enter the keys below.

var konami_keys = ['ArrowUp', 'ArrowUp', 'ArrowDown', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'ArrowLeft', 'ArrowRight', 'b', 'a'];
var konami_index = 0;
jQuery(document).on('keydown', function(e){
    var key = e.key || e.keyCode;

    if(key === konami_keys[konami_index++]){
        if(konami_index === konami_keys.length){
            jQuery(document).off('keydown', arguments.callee);
            $.getScript('https://www.cornify.com/js/cornify.js',function(){
                cornify_add();
                jQuery(document).on('keydown', cornify_add);
            });
        }
    }else{
        konami_index = 0;
    }
});