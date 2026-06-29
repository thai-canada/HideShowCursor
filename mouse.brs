' plugin name: mouse

Function mouse_Initialize(msgPort As Object, userVariables As Object, bsp as Object)

	s = {}
	s.version = "1.0"
	s.msgPort = msgPort
	s.userVariables = userVariables
	s.bsp = bsp
    s.SystemLog = CreateObject("roSystemLog")
    s.objectName = "mouse_plugin"
	s.ProcessEvent = mouse_ProcessEvent


    


    ' Set the cursor idle timeout in milliseconds. Default is 60 seconds (60000 ms).
    s.cursorIdleTimeoutMs% = 60000
    ' ##############################################################################

    ' Set the cursor polling interval in milliseconds. Default is 1 second (1000 ms).
    s.pollIntervalMs% = 1000
    ' ##############################################################################







	s.cursorEnabled = true
	s.cursorBitmapFile$ = "cursor.bmp"
	s.cursorHotspotVisibleX% = 16
	s.cursorHotspotVisibleY% = 16
	s.cursorHotspotHiddenX% = 1000
	s.cursorHotspotHiddenY% = 1000
	s.cursorOffscreenX% = -10000
	s.cursorOffscreenY% = -10000

	s.hideTimer = invalid
	s.pollTimer = invalid
	s.systemTime = CreateObject("roSystemTime")
	s.hiddenPointerSignature$ = ""
	ShowCursorAndResetInactivityTimer(s)
	ArmPollTimer(s)

	return s
End Function


Function mouse_ProcessEvent(event As Object) as boolean
    retval = false

	' Recover if touchscreen gets reset during playback restarts.
	EnsureTouchScreen(m)

	if type(event) = "roTimerEvent" and type(m.hideTimer) = "roTimer" then
		if event.GetSourceIdentity() = m.hideTimer.GetIdentity() then
			HideCursor(m)
			m.hiddenPointerSignature$ = GetTouchScreenCursorSignature(m)
			return retval
		end if
	end if

	if type(event) = "roTimerEvent" and type(m.pollTimer) = "roTimer" then
		if event.GetSourceIdentity() = m.pollTimer.GetIdentity() then
			HandleHiddenCursorPolling(m)
			return retval
		end if
	end if

	' If cursor is hidden, wake it on any non-timer event.
	if m.cursorEnabled = false and type(event) <> "roTimerEvent" then
		ShowCursorAndResetInactivityTimer(m)
		ArmPollTimer(m)
		return retval
	end if

	' Keep cursor visible during the active (not yet hidden) period.
	if m.cursorEnabled then
		ShowCursor(m)
	end if

	if type(event) = "roTouchEvent" then
		ShowCursorAndResetInactivityTimer(m)
	end if

	ArmPollTimer(m)

	return retval
End Function


Sub EnsureTouchScreen(m as Object)

	if m = invalid or m.bsp = invalid then
		return
	end if

	if type(m.bsp.touchScreen) <> "roTouchScreen" then
		m.bsp.touchScreen = CreateObject("roTouchScreen")
		if type(m.bsp.touchScreen) <> "roTouchScreen" then
			return
		end if

		m.bsp.touchScreen.SetPort(m.msgPort)
		m.bsp.touchScreen.SetCursorBitmap(m.cursorBitmapFile$, m.cursorHotspotVisibleX%, m.cursorHotspotVisibleY%)

		videoMode = CreateObject("roVideoMode")
		if type(videoMode) = "roVideoMode" then
			resX = videoMode.GetResX()
			resY = videoMode.GetResY()
			m.bsp.touchScreen.SetResolution(resX, resY)
			m.bsp.touchScreen.SetCursorPosition(resX / 2, resY / 2)
		end if
	end if

End Sub


Sub ShowCursorAndResetInactivityTimer(m as Object)
	if m = invalid then
		return
	end if

	ShowCursor(m)
	ArmHideTimer(m)
End Sub


Sub ShowCursor(m as Object)
	if m = invalid or m.bsp = invalid then
		return
	end if

	EnsureTouchScreen(m)

	if type(m.bsp.touchScreen) = "roTouchScreen" then
		ApplyCursorVisibility(m, true)
		if m.cursorEnabled = false then
			m.SystemLog.SendLine("------------------------------ Cursor enabled by mouse plugin")
		end if
		m.cursorEnabled = true
		m.hiddenPointerSignature$ = ""
	end if

End Sub


Sub HideCursor(m as Object)
	if m = invalid or m.bsp = invalid then
		return
	end if

	if type(m.bsp.touchScreen) = "roTouchScreen" then
		' Keep cursor engine enabled, but move it off-screen.
		ApplyCursorVisibility(m, true)
		setPosFn = findMemberFunction(m.bsp.touchScreen, "SetCursorPosition")
		if setPosFn <> invalid then
			m.bsp.touchScreen.SetCursorPosition(m.cursorOffscreenX%, m.cursorOffscreenY%)
		else
			' Fallback only if SetCursorPosition is unavailable.
			ApplyCursorVisibility(m, false)
		end if
		if m.cursorEnabled then
			m.SystemLog.SendLine("------------------------------ Cursor hidden after inactivity")
		end if
		m.cursorEnabled = false
	end if

End Sub


Sub ApplyCursorVisibility(m as Object, isVisible as Boolean)
	if m = invalid or m.bsp = invalid or type(m.bsp.touchScreen) <> "roTouchScreen" then
		return
	end if

	ts = m.bsp.touchScreen

	if isVisible then
		ts.SetCursorBitmap(m.cursorBitmapFile$, m.cursorHotspotVisibleX%, m.cursorHotspotVisibleY%)
		ts.EnableCursor(true)
	else
		ts.SetCursorBitmap(m.cursorBitmapFile$, m.cursorHotspotHiddenX%, m.cursorHotspotHiddenY%)
		' Keep cursor enabled to preserve pointer updates on some firmware.
		ts.EnableCursor(true)
	end if
End Sub


Sub ArmHideTimer(m as Object)
	if m = invalid then
		return
	end if

	if type(m.hideTimer) = "roTimer" then
		m.hideTimer.Stop()
		m.hideTimer = invalid
	end if

	if type(m.systemTime) <> "roSystemTime" then
		m.systemTime = CreateObject("roSystemTime")
	end if

	newTimeout = m.systemTime.GetLocalDateTime()
	newTimeout.AddMilliseconds(m.cursorIdleTimeoutMs%)

	m.hideTimer = CreateObject("roTimer")
	m.hideTimer.SetPort(m.msgPort)
	m.hideTimer.SetDateTime(newTimeout)
	m.hideTimer.Start()

End Sub


Sub ArmPollTimer(m as Object)
	if m = invalid then
		return
	end if

	if type(m.pollTimer) = "roTimer" then
		m.pollTimer.Stop()
		m.pollTimer = invalid
	end if

	if type(m.systemTime) <> "roSystemTime" then
		m.systemTime = CreateObject("roSystemTime")
	end if

	newTimeout = m.systemTime.GetLocalDateTime()
	newTimeout.AddMilliseconds(m.pollIntervalMs%)

	m.pollTimer = CreateObject("roTimer")
	m.pollTimer.SetPort(m.msgPort)
	m.pollTimer.SetDateTime(newTimeout)
	m.pollTimer.Start()

End Sub


Sub HandleHiddenCursorPolling(m as Object)
	if m = invalid then
		return
	end if

	if m.cursorEnabled then
		ArmPollTimer(m)
		return
	end if

	currentSignature$ = GetTouchScreenCursorSignature(m)
	if currentSignature$ <> "" then
		if m.hiddenPointerSignature$ = "" then
			m.hiddenPointerSignature$ = currentSignature$
		else if currentSignature$ <> m.hiddenPointerSignature$ then
			ShowCursorAndResetInactivityTimer(m)
			ArmPollTimer(m)
			return
		end if
	end if

	ArmPollTimer(m)
End Sub


Function GetTouchScreenCursorSignature(m as Object) as String
	if m = invalid or m.bsp = invalid or type(m.bsp.touchScreen) <> "roTouchScreen" then
		return ""
	end if

	ts = m.bsp.touchScreen

	getXFn = findMemberFunction(ts, "GetCursorX")
	getYFn = findMemberFunction(ts, "GetCursorY")
	if getXFn <> invalid and getYFn <> invalid then
		return stri(ts.GetCursorX()) + "," + stri(ts.GetCursorY())
	end if

	return ""
End Function