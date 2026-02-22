module github.com/Lakr233/ApplePackage/goipatoolwrapper

go 1.23.0

require (
	github.com/majd/ipatool/v2 v2.3.0
	howett.net/plist v1.0.0
)

replace github.com/99designs/keyring => ./third_party/keyring

require (
	github.com/99designs/keyring v1.2.2 // indirect
	github.com/mattn/go-colorable v0.1.13 // indirect
	github.com/mattn/go-isatty v0.0.17 // indirect
	github.com/mattn/go-runewidth v0.0.14 // indirect
	github.com/mitchellh/colorstring v0.0.0-20190213212951-d06e56a500db // indirect
	github.com/rivo/uniseg v0.2.0 // indirect
	github.com/rs/zerolog v1.28.0 // indirect
	github.com/schollz/progressbar/v3 v3.13.1 // indirect
	github.com/stretchr/testify v1.7.0 // indirect
	golang.org/x/sys v0.31.0 // indirect
	golang.org/x/term v0.30.0 // indirect
)
