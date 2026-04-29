// Vendored from https://www.cornify.com/js/cornify.js (fetched 2026-04-27).
//
// This file is bundled locally instead of being loaded from the cornify.com CDN
// at runtime so the application can run under a strict Content Security Policy
// (no remote script-src). The original source is preserved verbatim below; an
// ES module export of `cornify_add` is appended at the bottom so the Stimulus
// controller can import it as a default export.
//
// Note: cornify.js still references remote image and stylesheet URLs
// (https://www.cornify.com/...) at call time. Those need to be permitted by
// img-src / style-src in the CSP for the easter egg to render fully.

/*

    _______      ,-----.    .-------.    ,---.   .--..-./`)  ________    ____     __
   /   __  \   .'  .-,  '.  |  _ _   \   |    \  |  |\ .-.')|        |   \   \   /  /
  | ,_/  \__) / ,-.|  \ _ \ | ( ' )  |   |  ,  \ |  |/ `-' \|   .----'    \  _. /  '
,-./  )      ;  \  '_ /  | :|(_ o _) /   |  |\_ \|  | `-'`"`|  _|____      _( )_ .'
\  '_ '`)    |  _`,/ \ _/  || (_,_).' __ |  _( )_\  | .---. |_( )_   | ___(_ o _)'
 > (_)  )  __: (  '\_/ \   ;|  |\ \  |  || (_ o _)  | |   | (_ o._)__||   |(_,_)'
(  .  .-'_/  )\ `"/  \  ) / |  | \ `'   /|  (_,_)\  | |   | |(_,_)    |   `-'  /
 `-'`-'     /  '. \_/``".'  |  |  \    / |  |    |  | |   | |   |      \      /
   `._____.'     '-----'    ''-'   `'-'  '--'    '--' '---' '---'       `-..-'


*/

var cornify_count = 0;
var cornify_add = function(options) {
    // Track how often we cornified.
    cornify_count += 1;

    // Prepare our lovely variables.
    var cornify_url = 'https://www.cornify.com/';
    var numType = 'px';
    var heightRandom = Math.random() * 0.75;
    var windowHeight = 768;
    var windowWidth = 1024;
    var height = 0;
    var width = 0;
    var de = document.documentElement;
    var transform = 'translate(-50%, -50%)';
    var showGrandUnicorn = cornify_count == 15;

    // Create a container for our 'corn or 'bow.
    var div = document.createElement('div');
    div.style.position = 'fixed';
    div.className = '__cornify_unicorn';
    div.style.zIndex = 143143;
    div.style.outline = 0;
    div.onclick = cornify_add; // Click for more magic.

    // Get the window width and height - requires some cross browser checking.
    if(typeof(window.innerHeight) == 'number') {
        windowHeight = window.innerHeight;
        windowWidth = window.innerWidth;
    } else if(de && de.clientHeight) {
        windowHeight = de.clientHeight;
        windowWidth = de.clientWidth;
    } else {
        numType = '%';
        height = Math.round(height*100) + '%';
    }

    if(showGrandUnicorn) {
        // Clicking 15 times summons the grand unicorn - which is centered on the screen.
        div.style.top = '50%'
        div.style.left = '50%';
        div.style.zIndex = 143143143;
    } else {
        // Otherwise we randomize the position.
        div.style.top = Math.round(Math.random()*100) + '%';
        div.style.left = Math.round(Math.random()*100) + '%';

        transform += ' rotate('+Math.round(Math.random()*10-5)+'deg)';
    }

    // Create the image element.
    var img = document.createElement('img');
    img.style.opacity = 0;
    img.style.transition = "all .1s linear";
    img.alt = 'A lovely unicorn or rainbow';
    img.onload = function() {
        img.style.opacity = 1;
    };

    // Used as a cache buster so the browser makes a new request every time instead of usign the previous, cached one.
    var currentTime = new Date();
    var submitTime = currentTime.getTime();

    if(showGrandUnicorn) {
        // Caching doesn't matter for the Grand Unicorn.
        submitTime = 0;
    }

    // Construct our unicorn & rainbow request.
    var url = cornify_url+'getacorn.php?r='+submitTime+'&url='+document.location.href;

    // Add younicorns if requested.
    if(options && (options.y || options.younicorns)) {
        url += '&y='+(options.y ? options.y : options.younicorns);

        if(Math.random() > 0.5) {
            // Flip horizontally at random.
            if(transform.length > 0) {
                transform += ' scaleX(-1)';
            }
        };
    }

    div.style.transform = transform;
    div.style.MozTransform = transform;
    div.style.webkitTransform = transform;

    img.setAttribute('src', url);

    // Add a nice hover wigggle.
    img.style.transition = "all .1s linear";

    div.onmouseover = function() {
        var size = 1 + Math.round(Math.random()*10)/100;
        var angle = Math.round(Math.random()*20-10);
        var result = "rotate("+angle+"deg) scale("+size+","+size+")";
        img.style.transform = result;
        img.style.MozTransform = result;
        img.style.webkitTransform = result;
    };

    div.onmouseout = function() {
        var size = .9+Math.round(Math.random()*10)/100;
        var angle = Math.round(Math.random()*6-3);
        var result = "rotate("+angle+"deg) scale("+size+","+size+")";
        img.style.transform = result;
        img.style.MozTransform = result;
        img.style.webkitTransform = result;
    };

    // Append our container DIV to the page.
    var body = document.getElementsByTagName('body')[0];
    body.appendChild(div);
    div.appendChild(img);

    // Hooray - now we have a sparkly unicorn (or rainbow) on the page. Another cornification well done. Congrats!

    // When clicking 5 times, add a custom stylesheet to make the page look awesome.
    if(cornify_count == 5) {
        var cssExisting = document.getElementById('__cornify_css');

        if(!cssExisting) {
            var head = document.getElementsByTagName("head")[0];
            var css = document.createElement('link');
            css.id = '__cornify_css';
            css.type = 'text/css';
            css.rel = 'stylesheet';
            css.href = 'https://www.cornify.com/css/cornify.css';
            css.media = 'screen';
            head.appendChild(css);
        }
        cornify_replace();
    }

    cornify_updatecount();

    // Trigger an event on the document.
    var event = new Event('cornify');
    document.dispatchEvent(event);
};

// Tracks how often we cornified.
var cornify_updatecount = function() {
    var id = '__cornify_count';
    var p = document.getElementById(id);

    if(p == null) {
        var p = document.createElement('p');
        p.id = id;
        p.style.position = 'fixed';
        p.style.bottom = '5px';
        p.style.left = '0px';
        p.style.right = '0px';
        p.style.zIndex = '1000000000';
        p.style.color = '#ff00ff';
        p.style.textAlign = 'center';
        p.style.fontSize = '24px';
        p.style.fontFamily = "'Comic Sans MS', 'Comic Sans', 'Marker Felt', serif"; // Only the best!
        p.style.textTransform = 'uppercase';
        var body = document.getElementsByTagName('body')[0];
        body.appendChild(p);
    }

    if(cornify_count == 1) {
        p.innerHTML = 'You cornified!';
    } else {
        p.innerHTML = 'You cornified '+cornify_count+' times!';
    }

    // Stores our count in a cookie for our next session.
    cornify_setcookie('cornify', cornify_count+'', 1000);
};

var cornify_setcookie = function(name, value, days) {
    var d = new Date();
    d.setTime(d.getTime()+(days*24*60*60*1000));
    var expires = "expires="+d.toGMTString();
    document.cookie = name + "=" + value + "; " + expires;
};

var cornify_getcookie = function(cname) {
    var name = cname + "=";
    var ca = document.cookie.split(';');
    for(var i=0; i<ca.length; i++) {
        var c = ca[i].trim();
        if(c.indexOf(name)==0) {
            return c.substring(name.length,c.length);
        }
    }
    return "";
};

// Retrieve our click count from the cookie when we start up.
cornify_count = parseInt(cornify_getcookie('cornify'));
if(isNaN(cornify_count)) {
    cornify_count = 0;
}

// Adds happy words at the beginning of all headers on the page.
var cornify_replace = function() {
    // Replace text.
    var hc = 6;
    var hs;
    var h;
    var k;
    var words = ['Happy','Sparkly','Glittery','Fun','Magical','Lovely','Cute','Charming','Amazing','Wonderful'];
    while(hc >= 1) {
        hs = document.getElementsByTagName('h' + hc);
        for(k = 0; k < hs.length; k++) {
            h = hs[k];
            h.innerHTML = words[Math.floor(Math.random()*words.length)] + ' ' + h.innerHTML;
        }
        hc -= 1;
    }
};

// Adds happy words at the beginning of all headers on the page.
var cornify_replace = function() {
    var headerTypeIndex = 6;
    var headerElements;
    var headerElement;
    var i;
    var magicalWords = ['Happy', 'Sparkly', 'Glittery', 'Fun', 'Magical', 'Lovely', 'Cute', 'Charming', 'Amazing', 'Wonderful'];

    while(headerTypeIndex >= 1) {
        headerElements = document.getElementsByTagName('h' + headerTypeIndex);

        for(i = 0; i < headerElements.length; i++) {
            headerElement = headerElements[i];
            headerElement.innerHTML = magicalWords[Math.floor(Math.random()*magicalWords.length)] + ' ' + headerElement.innerHTML;
        }

        headerTypeIndex -= 1;
    }
};

// Clicking the rainbow cupcake button makes all the unicorns
// disappear (should only be used in an emergency, since it's sad).
var cornify_click_cupcake_button = function() {
    var doc = document;

    var corns = doc.getElementsByClassName('__cornify_unicorn');
    if(corns) {
        for(var i=0; i<corns.length; i++) {
            corns[i].parentNode.removeChild(corns[i]);
        }
    }

    // Remove our counter.
    var button = doc.getElementById('__cornify_count');
    if(button) {
        button.parentNode.removeChild(button);
    }

    // Remove the cupcake button.
    var button = doc.getElementById('__cornify_cupcake_button');
    if(button) {
        button.parentNode.removeChild(button);
    }

    var event = new Event('cornify-clear');
    document.dispatchEvent(event);
};

// Add the rainbow cupcake button to the page.
var cornify_add_cupcake_button = function() {
    var id = '__cornify_cupcake_button';
    var doc = document;
    var button = doc.getElementById(id);

    if(!button) {
        button = doc.createElement('div');
        button.id = id;
        button.onclick = cornify_click_cupcake_button;
        button.style.position = 'fixed';
        button.style.top = '10px';
        button.style.right = '10px';
        button.style.zIndex = 2147483640;
        button.setAttribute('aria-label', 'Hide unicorns and rainbows');

        var image = document.createElement('img');
        image.src = 'https://www.cornify.com/assets/cornify-cupcake-button.png';
        image.alt = 'Cupcake button';
        image.width = 50;
        image.height = 50;
        image.style.width = '50px !important';
        image.style.height = '50px !important';
        image.style.display = 'block !important';
        image.style.cursor = 'pointer !important';
        image.style.margin = '0 !important';
        image.style.padding = '0 !important';
        button.appendChild(image);

        doc.getElementsByTagName('body')[0].appendChild(button);
    }
};

// Note: the upstream cornify.js bundles its own Konami-code listener (the
// `cornami` object) which auto-attaches a window.document.onkeydown handler.
// We intentionally omit that block because the konami_code Stimulus controller
// owns sequence detection in this app, and we don't want to clobber any other
// document.onkeydown handler that Rails or our Stimulus stack may install.

// Expose cornify_add as the default export for ES module consumers (and keep
// the original function names available as named exports for parity with the
// upstream library).
export default cornify_add;
export { cornify_add, cornify_add_cupcake_button, cornify_click_cupcake_button };
