Traffic
========

A NPC traffic system for Just Cause 2 Multiplayer.

The server will simulate vehicles (500 by default) driving randomly around Panau.
See `shared/config.lua` for configurable values.

The road naviagtion mesh is stored in a binary file called `GroundVehicleNavigation`.
I took this from the JCMP-AI script by jaxm, which I 've been told on the jc2mp discord that
it was Sinister Rectus who gathered that data.

## Technical Bits
The server simulates virtual vehicles as `WorldNetworkObjects` and replicates that to the clients.
The clients then create a `ClientActor` and attaches them to each streamed vehicle and uses a
bunch of PID controllers to calculate what the accelerate and turn inputs should be.

By Luke Perkin (Perky)