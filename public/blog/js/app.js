function d3go() {
  var circles = d3.selectAll("#three circle")
  jiggle(circles)
  if (typeof d3ready !== 'undefined') {
    d3ready()
  }
}

function jiggle(things) {
  things.transition()
        .delay(200)
        .duration(7100)
        .ease('elastic')
        .attr("cx", function(who) {return 10+(Math.random() * 190); })
        .each("end", function(){jiggle(things)})
}
