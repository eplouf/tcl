#!/usr/bin/tclsh

# smat [serveur monitoring apache times]
#		(peut fonctionner bien sur avec d'autre serveur que apache;)
# daemon for serving data to cacti graphs or whatever, based on web logs only

# voici les array utilises:
#		FileList - clef filename, value handle
#		Varray - clef vhost + type, value info
# en fait, je mixe tout la, avec des types devant comme file*,count,dalnreq,...
# on verra si le hash ne sera pas meilleure avec du contenu <:)

# 2007/02/23 12:49:09 eldre
# fichier date du 16 mai 2008

# TODO
#		- je devrai faire un namespace avec les actions faites sur FileList


# pour acceder a translit, qui vaut un string map ...ahum
package require Tclx

# on fait l'action voulue
proc Action { vhost line } {
	global Varray
	variable count

	# on compte combien de fois on a vu ce vhost
	set count [expr $Varray(count$vhost) + 1]
	array set Varray "count$vhost $count"

	# on recupere les champs clefs du log apache
	set ap_re {^([0-9\.]+) - "([^"]+)" \[([0-9a-zA-Z:+/ ]+)\] "([^"]+)" ([0-9\-]+) ([0-9\-]+) ([0-9\-]+) ([0-9\-]+) "([^"]+)" "([^"]+)" "([^"]+)" "([^"]+)" "([^"]+)" "([^"]+)" "([^"]+)" ([0-9]+)$}
	regexp $ap_re $line toto ip uid date get ecode bytesdoc delai pid ua referer dalnreq dalttime dalmtime daltbyte contenttype timeserving
	if { [catch {
		if { "$dalnreq" == "-" } { set dalnreq 0 }
		if { "$dalttime" == "-" } { set dalttime 0 }
		if { "$dalmtime" == "-" } { set dalmtime 0 }
		if { "$daltbyte" == "-" } { set daltbyte 0 }
	} out] } {
		#puts "-- Parsing error on $vhost:\n\t$line"
		return
	}

	array set Varray "tts$vhost [expr [lindex [translit , { } $Varray(tts$vhost)] 0] + $delai],$count"
	array set Varray "dalnreq$vhost [expr [lindex [translit , { } $Varray(dalnreq$vhost)] 0] + $dalnreq],$count"
	array set Varray "dalttime$vhost [expr [lindex [translit , { } $Varray(dalttime$vhost)] 0] + $dalttime],$count"
	array set Varray "dalmtime$vhost [expr [lindex [translit , { } $Varray(dalmtime$vhost)] 0] + $dalmtime],$count"
	array set Varray "daltbyte$vhost [expr [lindex [translit , { } $Varray(daltbyte$vhost)] 0] + $daltbyte],$count"

	unset count
}

proc AuthValid { channel } {
	global AuthList

	if { ![info exists AuthList] } {
		set AuthList ""
	}
	if { [lsearch $AuthList $channel] < 0 } {
		return false
	}
	return true
}

proc DoAuth { channel } {
	if { [eof $channel] } {
		close $channel
		return false
	}

	global AuthList

	while { [gets $channel line] > 0 } {
		if { [string equal $line "smatchit"] } {
		puts "== $line"
			concat $AuthList $channel
			return true
		}
	}
	return false
}

proc RemoveAuth { channel } {
	global AuthList
	variable i

	if { [info exists AuthList] } {
		set i [lsearch $AuthList $channel]
		if { $i < 0 } {
			return false
		}
		lreplace $AuthList $i $i ""
	}
}

# centre de controle, on gere le serveur en telnet possible
proc Cmd { channel } {
	global Varray
	variable fd
	variable vhost

	#puts "ohhh $channel"
	#if { ![AuthValid $channel] } {
	#	puts "no auth found for $channel"
	#	if { ![DoAuth $channel] } {
	#		close $channel
	#		return
	#	}
	#}
	if { [eof $channel] } {
		#RemoveAuth $channel
		close $channel
		return
	}
	gets $channel line
	switch [lindex $line 0] {
		hello {
			puts $channel "hello, world"
		}
		info {
			#Display files actually open, may be a long list
			foreach { filename handle } [array get Varray file*] {
				puts $channel "[crange $filename 4 end]: $handle"
			}
		}
		internal {
			if { [info exists Varray] } {
				puts $channel "=== Varray"
				puts $channel [array statistics Varray]
			}
			puts $channel "=== after"
			puts $channel [after info]
		}
		add {
			set ecode [catch {open [lindex $line 1] r} fd]
			if { $ecode } {
				puts $channel "I can't access this file :("
			} else {
				fconfigure $fd -buffering line
				set vhost [file tail [file dirname [lindex $line 1]]]
				array set Varray "file[lindex $line 1] $fd"
				array set Varray "count$vhost 0"
				array set Varray "tts$vhost 0,0"
				array set Varray "dalnreq$vhost 0,0"
				array set Varray "dalttime$vhost 0,0"
				array set Varray "dalmtime$vhost 0,0"
				array set Varray "daltbyte$vhost 0,0"
			}
		}
		remove {
			close $Varray(file[lindex $line 1])
			array unset Varray file[lindex $line 1]
			set vhost [file tail [file dirname [lindex $line 1]]]
			array unset Varray count$vhost
			array unset Varray tts$vhost
			array unset Varray dalnreq$vhost
			array unset Varray dalttime$vhost
			array unset Varray dalmtime$vhost
			array unset Varray daltbyte$vhost
		}
		logout {
			#RemoveAuth $channel
			close $channel
			return
		}
		stop {
			if { [lindex $line 1] == "secretme" } {
				global Sstat
				global Scmd
				# on close tout
				close $Sstat
				close $Scmd
				foreach file [array names Varray file*] {
					close $Varray($file)
				}
				return
			}
		}
		default {
			puts $channel "command not recognized"
		}
	}
	puts -nonewline $channel "> "
	flush $channel
}

# cacti viendra se connecter pour obtenir ses stats
# envoie du nombre de ligne prise pour un vhost, ainsi que la somme des temps d'appels
proc Stats { channel } {
	if { [eof $channel] } {
		#RemoveAuth $channel
		close $channel
		return
	}
	#if { ![AuthValid $channel] } {
	#	if { ![DoAuth $channel] } {
	#		close $channel
	#		return
	#	}
	#}
	global Varray
	variable vhost
	variable line

	gets $channel line
	switch -- [lindex $line 0] {
		get {
			set vhost [lindex $line 2]
			if { $vhost == "" } {
				puts $channel "wrong command"
				break
			}
			if { ![info exists Varray(count$vhost)] } {
				puts $channel "wrong command"
				break
			}
			switch -- [lindex $line 1] {
				count {
					puts $channel $Varray(count$vhost)
					array set Varray "count$vhost 0"
				}
				time {
					puts $channel $Varray(tts$vhost)
					array set Varray "tts$vhost 0,0"
				}
				dalnreq {
					puts $channel $Varray(dalnreq$vhost)
					array set Varray "dalnreq$vhost 0,0"
				}
				dalttime {
					puts $channel $Varray(dalttime$vhost)
					array set Varray "dalttime$vhost 0,0"
				}
				dalmtime {
					puts $channel $Varray(dalmtime$vhost)
					array set Varray "dalmtime$vhost 0,0"
				}
				daltbyte {
					puts $channel $Varray(daltbyte$vhost)
					array set Varray "daltbyte$vhost 0,0"
				}
				default {
					puts $channel "need a command"
				}
			}
		}
		logout {
			#RemoveAuth $channel
			close $channel
			return
		}
		info {
			foreach filename [array names Varray file*] {
				set vhost [file tail [file dirname [crange $filename 4 end]]]
				puts $channel "$vhost"
			}
		}
		default {
			puts $channel "need a command"
		}
	}
	puts -nonewline $channel "> "
	flush $channel
}

proc SrvCmd { channel caddr cport } {
	puts -nonewline $channel "> "
	flush $channel
	fconfigure $channel -blocking 0
	fconfigure $channel -buffering line
	fileevent $channel readable "Cmd $channel"
}

proc SrvStats { channel caddr cport } {
	puts -nonewline $channel "> "
	flush $channel
	fconfigure $channel -blocking 0
	fconfigure $channel -buffering line
	fileevent $channel readable "Stats $channel"
}

proc ScanFiles {} {
	global Varray
	variable Fstatus
	variable vhost

	foreach { filename handle } [array get Varray file*] {
		set vhost [file tail [file dirname $filename]]
		set filename [crange $filename 4 end]
		while { [gets $handle line] > 0 } {
			Action $vhost $line
		}
		# attention, ce cas est consomateur de ressources!
		#if { [eof $handle] } { 
		#	catch {close $handle} out
		#	array set Varray "file$filename [open $filename r]"
		#}
	}
	after 2000 ScanFiles
}

##########
##### main

global Varray
variable vhost
variable fid
variable file
variable dir
variable Scmd
variable Sstat

# on ouvre tout ce qu'il nous faut
set dir "/mnt/logs/apache_logs/*/access_log"
foreach file [glob $dir] {
	if { [file readable $file] } {
		set fid [open $file r]
		set vhost [file tail [file dirname $file]]
		fconfigure $fid -buffering line
		array set Varray "file$file $fid"
		array set Varray "count$vhost 0"
		array set Varray "tts$vhost 0,0"
		array set Varray "dalnreq$vhost 0,0"
		array set Varray "dalttime$vhost 0,0"
		array set Varray "dalmtime$vhost 0,0"
		array set Varray "daltbyte$vhost 0,0"
	}
}

# on lance l'instance serveur de commandes
set Scmd [socket -server SrvCmd 5001]
# on lance l'instance qui va ecouter les demandes depuis cacti
set Sstat [socket -server SrvStats 5000]

after 5000 ScanFiles
vwait forever

# on close tout
close $Sstat
close $Scmd
foreach file [array names Varray file*] {
	close $Varray([crange $file 4 end])
}

