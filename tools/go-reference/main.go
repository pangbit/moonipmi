// A loopback-only fixture around the pinned, unmodified go-ipmi reference BMC.
// All state and credentials are synthetic; no real hardware HAL is connected.
package main

import (
	"context"
	"encoding/json"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/bougou/go-ipmi/pkg/bmc"
	"github.com/bougou/go-ipmi/pkg/hal/mock"
	"github.com/bougou/go-ipmi/pkg/server"
	"github.com/bougou/go-ipmi/pkg/transport/udp"
	"github.com/bougou/go-ipmi/pkg/types"
)

func run() error {
	hardware := mock.New()
	hardware.Chassis().(*mock.Chassis).On = true
	hardware.Sensors().(*mock.Sensors).Values = map[uint8]uint8{0x2a: 42}
	info := bmc.DeviceInfo{
		DeviceID: 0x12, DeviceRevision: 3, FirmwareMajor: 1,
		FirmwareMinor: 0x23, IPMIVersion: 0x02,
		ManufacturerID: 343, ProductID: 0x1234,
	}
	var guid [16]byte
	copy(guid[:], "synthetic-bmc-id")
	device := bmc.New(info, guid, hardware)
	user, err := device.Users.Add(2, "tester")
	if err != nil {
		return err
	}
	user.SetPassword([]byte("synthetic-password"))
	user.Enabled = true
	user.ChannelAccess[1] = bmc.UserChannelAccess{
		MaxPrivilege: bmc.PrivilegeLevelUser,
		Enabled:      true,
	}
	conn, err := udp.Listen("127.0.0.1:0")
	if err != nil {
		return err
	}
	defer conn.Close()
	service := server.NewServer(device, conn,
		server.WithCipherSuites([]types.CipherSuiteID{17}),
		server.WithV15Disabled())
	defer service.Close()
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	go func() {
		<-ctx.Done()
		_ = service.Close()
	}()
	if err := json.NewEncoder(os.Stdout).Encode(map[string]int{
		"port": conn.LocalAddr().(*net.UDPAddr).Port,
	}); err != nil {
		return err
	}
	return service.Serve(ctx)
}

func main() {
	if err := run(); err != nil {
		log.Fatal(err)
	}
}
