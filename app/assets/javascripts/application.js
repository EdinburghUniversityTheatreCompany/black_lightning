// This is a manifest file that'll be compiled into application.js, which will include all the files
// listed below.
//
// Any JavaScript/Coffee file within this directory, lib/assets/javascripts, vendor/assets/javascripts,
// or vendor/assets/javascripts of plugins, if any, can be referenced here using a relative path.
//
// It's not advisable to add code directly here, but if you do, it'll appear at the bottom of the
// the compiled file.
//
// WARNING: THE FIRST BLANK LINE MARKS THE END OF WHAT'S TO BE PROCESSED, ANY BLANK LINE SHOULD
// GO AFTER THE REQUIRES BELOW.
//
//= require jquery
//= require jquery_ujs
//= require jquery_nested_form
//= require raphael-min
//= require dracula_graffle
//= require dracula_graph
//= require bootstrap
//= require alerts
//= require jquery-ui-1.9.2.custom
//= require slimScroll.min
//= require jquery.lightbox-0.5
//= require lightbox-init

var konami_keys = [38, 38, 40, 40, 37, 39, 37, 39, 66, 65];
var konami_index = 0;
$(document).keydown(function(e){
    if(e.keyCode === konami_keys[konami_index++]){
        if(konami_index === konami_keys.length){
            $(document).unbind('keydown', arguments.callee);
            $.getScript('http://www.cornify.com/js/cornify.js',function(){
                cornify_add();
                $(document).keydown(cornify_add);
            }); 
        }
    }else{
        konami_index = 0;
    }
});