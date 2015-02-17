function d3go() {
  var circles = d3.selectAll("#three circle")
  circles.transition()
        .delay(200)
        .duration(7100)
        .ease('elastic')
        .attr("cx", function(who) {return Math.random() * 120; });
  if (typeof d3ready !== 'undefined') {
    d3ready()
  }
}