// Fixed-loopback comparison adapter; only public synthetic credentials and reads.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strconv"
	"time"

	ipmi "github.com/bougou/go-ipmi/pkg/client"
	"github.com/bougou/go-ipmi/pkg/types"
)

func run() (err error) {
	if len(os.Args) != 3 {
		return fmt.Errorf("usage: reference-client <local mock port> <scenario>")
	}
	port, err := strconv.Atoi(os.Args[1])
	if err != nil || port < 1 || port > 65535 {
		return fmt.Errorf("invalid local port")
	}
	scenario := os.Args[2]
	switch scenario {
	case "device", "chassis", "sensor", "bad-password", "completion":
	default:
		return fmt.Errorf("unknown synthetic comparison case")
	}
	password := "synthetic-password"
	if scenario == "bad-password" {
		password = "wrong-synthetic-key"
	}
	c, err := ipmi.NewClient("127.0.0.1", port, "tester", password)
	if err != nil {
		return err
	}
	c.WithInterface(ipmi.InterfaceLanplus).WithCipherSuiteID(types.CipherSuiteID(17)).
		WithMaxPrivilegeLevel(types.PrivilegeLevelUser).WithRetry(0).
		WithTimeout(time.Second).WithDebug(false)
	defer func() {
		ctx, cancel := context.WithTimeout(context.Background(), time.Second)
		defer cancel()
		if closeErr := c.Close(ctx); err == nil {
			err = closeErr
		}
	}()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err = c.Connect(ctx); err != nil {
		return err
	}
	var result any
	switch scenario {
	case "device", "bad-password":
		d, e := c.GetDeviceID(ctx)
		if e != nil {
			return e
		}
		result = map[string]any{
			"device_id": d.DeviceID, "device_revision": d.DeviceRevision,
			"firmware_major": d.MajorFirmwareRevision, "firmware_minor": d.MinorFirmwareRevision,
			"ipmi_major": d.MajorIPMIVersion, "ipmi_minor": d.MinorIPMIVersion,
			"manufacturer_id": d.ManufacturerID, "product_id": d.ProductID,
			"firmware_available": d.DeviceAvailable,
		}
	case "chassis":
		s, e := c.GetChassisStatus(ctx)
		if e != nil {
			return e
		}
		result = map[string]any{
			"power_on": s.PowerIsOn, "power_overload": s.PowerOverload,
			"power_interlock": s.InterLock, "power_fault": s.PowerFault,
			"power_control_fault": s.PowerControlFault, "restore_policy": s.PowerRestorePolicy,
		}
	default:
		number := uint8(0x2a)
		if scenario == "completion" {
			number = 0xff
		}
		s, e := c.GetSensorReading(ctx, number)
		if e != nil {
			return e
		}
		result = map[string]any{
			"raw_reading": s.Reading, "reading_available": !s.ReadingUnavailable,
			"scanning_enabled": !s.SensorScanningDisabled, "events_enabled": !s.EventMessagesDisabled,
			"status_bits": []int{int(s.OptionalData1)},
		}
	}
	return json.NewEncoder(os.Stdout).Encode(result)
}

func main() {
	if err := run(); err != nil {
		var responseError *types.ResponseError
		if errors.As(err, &responseError) {
			fmt.Fprintf(os.Stderr, "FAIL: completion code %d\n", responseError.CompletionCode())
		}
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
