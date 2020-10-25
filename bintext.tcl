#!/usr/bin/wish

package require Tk
package require Expect

text .textIO
frame .butF
button .butF.butDEC -text "Decode"
button .butF.butENC -text "Encode"
button .butF.butMask -text "ASCII art"
button .butF.butClear -text "Clear"
button .butF.butOpen -text "Open a file"
button .butF.butSave -text "Save to a file"

pack .textIO -expand 1 -fill both -side top
pack .butF -fill both -side bottom
pack .butF.butDEC -fill x -expand 1 -side bottom
pack .butF.butENC -fill x -expand 1 -side bottom
pack .butF.butClear -fill x -expand 1 -side left
pack .butF.butMask -fill x -expand 1 -side left
pack .butF.butOpen -fill x -side left
pack .butF.butSave -fill x -side right

wm title . {binary text}
focus .textIO

.butF.butClear configure -command {
	.textIO delete 0.0 end
}

.butF.butOpen configure -command {
	set textfile [tk_getOpenFile -title "Open a text file"]
	if { $textfile == {} } {
		return
	}
	set readfrom [open $textfile r]
	set idx 1
	while { [gets $readfrom line] > -1 } {
		.textIO insert $idx.0 "$line\n"
		incr idx
	}
	close $readfrom
}

.butF.butSave configure -command {
	set savedfile [tk_getSaveFile -title "Save your precious content"]
	if { $savedfile == {} } {
		return
	}
	set saveto [open $savedfile w+]
	puts $saveto [.textIO get 0.0 end]
	close $saveto
}

.butF.butENC configure -command {
	set buffer [string trim [.textIO get 0.0 end]]
	set length [string length $buffer]
	set i 0
	while { $i < $length } {
		set char [string range $buffer $i $i]
		incr i
		#set hchar [scan $char "%c"]
		set binary [binary scan $char B8B var1 var2]
		lappend binaries $var1
	}
  .textIO delete 0.0 end
	.textIO insert 0.0 [join $binaries ""]
	unset binaries
}
.butF.butDEC configure -command {
	set buffer [.textIO get 0.0 end]
	set length [string length $buffer]
	set i 0
	set count 0
	set texties ""
	set bytes {}
	while { $i < $length } {
		set char [string range $buffer $i $i]
		if { $count == 8 } {
			set count 0
			set word [join $bytes ""]
			set texty [binary format B8 $word]
			unset word
			unset bytes
			lappend texties $texty
			unset texty
		}
		if { $char == "0" || $char == "1" } {
			lappend bytes $char
			incr count
		}
		incr i
	}
	.textIO delete 0.0 end
	.textIO insert 0.0 "\n[join $texties ""]\n"
	unset texties
}

.butF.butMask configure -command {
	set maskfile [tk_getOpenFile -title "Choose mask file"]
	if { $maskfile == {} } {
		return
	}
	set mf [open $maskfile r]
	set txtBoxIdx 1
	set txtBoxCharLineIdx 0
	set txtboxline [.textIO get $txtBoxIdx.0 $txtBoxIdx.end]
	.textIO delete 0.0 end
	set txtBoxLineLen [string length $txtboxline]
	while { [gets $mf maskline] > 0 } {
		if { $txtBoxCharLineIdx <= $txtBoxLineLen } {
			for { set maskCharIdx 0 } { $maskCharIdx < [string length $maskline] } { incr maskCharIdx } {
				set maskchar [string range $maskline $maskCharIdx $maskCharIdx]
				if { $maskchar != " " } {
						if { $txtBoxCharLineIdx < $txtBoxLineLen } {
						set chartxtline [string range $txtboxline $txtBoxCharLineIdx $txtBoxCharLineIdx]
						incr txtBoxCharLineIdx
						# replace chartxtline inside maskline
						set splitted [split $maskline {}]
						lset splitted $maskCharIdx $chartxtline
						set maskline [join $splitted {}]
						unset splitted
					}
				}
			}
		}
		.textIO insert $txtBoxIdx.0 "$maskline\n"
		incr txtBoxIdx
	}
	close $mf
	if { $txtBoxCharLineIdx <= $txtBoxLineLen } {
		.textIO insert 0.0 "finished! at $txtBoxCharLineIdx vs $txtBoxLineLen, no more space!\n"
		#set txtboxlineSplitted [split $txtboxline {}]
		#set txtboxLineSplitted [lrange $txtboxlineSplitted $txtBoxCharLineIdx end]
		#.textIO insert 1.0 "do something (another art?) with that:\n[join $txtboxLineSplitted {}]\n"
		.textIO insert end "do something (another art?) with that:\n[string range $txtboxline $txtBoxCharLineIdx end]\n"
	}
}
