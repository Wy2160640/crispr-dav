function hideshow(id){
	obj=document.getElementById(id)
	if (!obj) return

	if (obj.style.display=="block")
		obj.style.display="none"
	else
		obj.style.display="block"
}

function toggleImg(id) {
	var theImg = document.getElementById(id)
	if (!theImg) return
	var x=theImg.src.split("/")
	var t=x.length - 1
	var y=x[t]
	if (y=='plus.jpg')
		theImg.src="assets/minus.jpg"
	else if (y=='minus.jpg')
		theImg.src="assets/plus.jpg"
}

function showCharts( crispr_name ) {
    var sample=document.getElementById("select1").value;
	var high_res=document.getElementById("high_res").value;
	var plot_ext= high_res ? ".tif" : ".png";
    var str = "";
    if ( sample) {
        var types = ["ins", "del", "len", "len2"];
        str = "<table border=0>";
        for (i=0; i< types.length; i++) {
            if ( i%2 ==0 ) { str +="<tr>"; }
            str += "<td><img src=assets/" + sample + "." + crispr_name + "." + types[i] + plot_ext + "></td>";
            if ( i%2 == 1 ) { str +="</tr>"; }
        }
        str += "</tr>";

        // chart for snp
        str += "<tr><td colspan=2><img src=assets/" + sample + "." + crispr_name + ".snp" + plot_ext + "></td></tr>";
        str += "</table>";
    }
    document.getElementById("charts").innerHTML = str;
}

