// General resources:
// How to use webpacker: https://stackoverflow.com/questions/54501241/rails-5-6-how-to-include-js-functions-with-webpacker/56549843

import * as Viva from 'vivagraphjs/dist/vivagraph.js'

function DrawTree(json) {
  // How to use a container: https://stackoverflow.com/questions/29137856/how-to-avoid-vivagraph-renders-the-graph-outside-of-the-container

  var container = document.getElementById('techie-tree-container')
  var graph = Viva.Graph.graph();

  // add a simple node

  for (var techie of json.nodes) {
    // TODO: Names and stff. Check this https://stackoverflow.com/questions/29137856/how-to-avoid-vivagraph-renders-the-graph-outside-of-the-container
    graph.addNode(techie.id, { "label": techie.name } );
  }

  for (var edge of json.edges) {
    // TOOD: Direction https://github.com/anvaka/VivaGraphJS/blob/master/demos/tutorial_svg/05%20-%20Edges%20With%20Arrows.html
    graph.addLink(edge[0], edge[1], { directed: true });
  }

  var layout = Viva.Graph.Layout.forceDirected(graph, {
      springLength : 100,
      springCoeff : 0.000001,
      dragCoeff : 0.04,
      gravity : -1.2
  });

  var graphics = Viva.Graph.View.svgGraphics();
  var nodeSize = 24;

  // http://jsfiddle.net/2LQmB/1/
  // TODO: Boxes, which should not overlap.
	graphics.node(
    function(node) {
      var ui = Viva.Graph.svg('g'),
      svgText = Viva.Graph.svg('text').attr('y', '-4px').attr('x',
          '-' + (nodeSize / 4) + 'px').text(node.data.label),

      img = node.data.image ? Viva.Graph.svg('image').attr('width',
          nodeSize).attr('height', nodeSize)
          .link(
              'https://secure.gravatar.com/avatar/'
                  + node.data.image) : Viva.Graph.svg(
          'rect').attr('width', nodeSize)
          .attr('height', nodeSize).attr('fill',
              node.data.color ? node.data.color : '#00a2e8');

      ui.append(svgText);

      return ui;
    }).placeNode(
    function(nodeUI, pos) {
      nodeUI.attr('transform', 'translate(' + pos.x  + ',' + pos.y + ')');

      //nodeUI.attr('transform', 'translate(' + (pos.x - nodeSize / 2) + ',' + (pos.y - nodeSize / 2) + ')');
    });



  var renderer = Viva.Graph.View.renderer(graph, {
      layout : layout,
      container: container,
      graphics: graphics
  });

  renderer.run();
}



window.addEventListener('load', function() {
  // https://stackoverflow.com/questions/12460378/how-to-get-json-from-url-in-javascript
  fetch('/admin/techies/tree_data.json')
  .then(res => res.json())
  .then(out =>
    DrawTree(out)
  ); 
})

// TODO: Center a node when you click it.
// layout.setNodePosition(nodeId, x, y)