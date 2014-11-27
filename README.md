[![Build Status](https://travis-ci.org/GaloisInc/tower.svg?branch=tower-9)](https://travis-ci.org/GaloisInc/tower)

# [Tower][tower]

## About

Tower is a concurrency framework for the [Ivory language][ivory]. Tower
composes Ivory programs into monitors which communicate with synchronous
channels.

Tower uses pluggable backends to support individual operating systems and
target architectures. A backend for the [FreeRTOS][freertos] operating
system running on the [STM32][] line of microcontrollers is available in
the [ivory-tower-stm32][] repo.

[![Build Status](https://travis-ci.org/GaloisInc/tower.svg?branch=tower-9)](https://travis-ci.org/GaloisInc/tower)

## Copyright and license
Copyright 2014 [Galois, Inc.][galois]

Licensed under the BSD 3-Clause License; you may not use this work except in
compliance with the License. A copy of the License is included in the LICENSE
file.

[ivory]: http://github.com/GaloisInc/ivory
[tower]: http://github.com/GaloisInc/tower
[ivory-tower-stm32]: http://github.com/GaloisInc/ivory-tower-stm32
[overview]: http://smaccmpilot.org/software/tower-overview.html

[STM32]: http://www.st.com/stm32
[freertos]: http://freertos.org
[galois]: http://galois.com


