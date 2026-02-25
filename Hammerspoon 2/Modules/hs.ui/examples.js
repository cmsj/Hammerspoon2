// hs.ui Module Examples
// These examples demonstrate the capabilities of the hs.ui module

// Example 1: Simple colored rectangle
function example1_simpleRectangle() {
    hs.ui.window({x: 100, y: 100, w: 200, h: 200})
        .rectangle()
            .fill("#FF0000")
            .frame({w: "100%", h: "100%"})
        .show();
}

// Example 2: Circle with stroke
function example2_circleStroke() {
    hs.ui.window({x: 350, y: 100, w: 200, h: 200})
        .circle()
            .stroke("#0000FF")
            .strokeWidth(5)
            .frame({w: 150, h: 150})
        .backgroundColor("#FFFFFF")
        .show();
}

// Example 3: Text element
function example3_text() {
    hs.ui.window({x: 600, y: 100, w: 300, h: 150})
        .text("Hello, Hammerspoon!")
            .font(HSFont.title())
            .foregroundColor("#FFFFFF")
        .backgroundColor("#000000")
        .show();
}

// Example 4: Vertical stack layout
function example4_vstack() {
    hs.ui.window({x: 100, y: 350, w: 300, h: 400})
        .vstack()
            .spacing(15)
            .padding(20)
            .text("Dashboard")
                .font(HSFont.largeTitle())
                .foregroundColor("#FFFFFF")
            .rectangle()
                .fill("#4A90E2")
                .cornerRadius(10)
                .frame({w: "90%", h: 80})
            .rectangle()
                .fill("#50C878")
                .cornerRadius(10)
                .frame({w: "90%", h: 80})
            .rectangle()
                .fill("#FF6B6B")
                .cornerRadius(10)
                .frame({w: "90%", h: 80})
        .end()
        .backgroundColor("#2C3E50")
        .show();
}

// Example 5: Horizontal stack layout
function example5_hstack() {
    hs.ui.window({x: 450, y: 350, w: 400, h: 150})
        .hstack()
            .spacing(20)
            .padding(20)
            .circle()
                .fill("#FF6B6B")
                .frame({w: 80, h: 80})
            .vstack()
                .spacing(5)
                .text("Status Indicator")
                    .font(HSFont.headline())
                    .foregroundColor("#FFFFFF")
                .text("System is running")
                    .font(HSFont.body())
                    .foregroundColor("#CCCCCC")
            .end()
        .end()
        .backgroundColor("#34495E")
        .show();
}

// Example 6: Complex nested layout
function example6_nested() {
    hs.ui.window({x: 900, y: 350, w: 350, h: 450})
        .vstack()
            .spacing(20)
            .padding(20)
            .text("Activity Monitor")
                .font(HSFont.title())
                .foregroundColor("#FFFFFF")
            .hstack()
                .spacing(15)
                .circle()
                    .fill("#50C878")
                    .frame({w: 60, h: 60})
                .vstack()
                    .spacing(5)
                    .text("CPU")
                        .font(HSFont.headline())
                        .foregroundColor("#FFFFFF")
                    .text("45%")
                        .font(HSFont.body())
                        .foregroundColor("#50C878")
                .end()
            .end()
            .hstack()
                .spacing(15)
                .circle()
                    .fill("#4A90E2")
                    .frame({w: 60, h: 60})
                .vstack()
                    .spacing(5)
                    .text("Memory")
                        .font(HSFont.headline())
                        .foregroundColor("#FFFFFF")
                    .text("8.2 GB")
                        .font(HSFont.body())
                        .foregroundColor("#4A90E2")
                .end()
            .end()
            .hstack()
                .spacing(15)
                .circle()
                    .fill("#FF6B6B")
                    .frame({w: 60, h: 60})
                .vstack()
                    .spacing(5)
                    .text("Disk")
                        .font(HSFont.headline())
                        .foregroundColor("#FFFFFF")
                    .text("234 GB")
                        .font(HSFont.body())
                        .foregroundColor("#FF6B6B")
                .end()
            .end()
        .end()
        .backgroundColor("#1E1E1E")
        .show();
}

// Example 7: Simple alert
function example7_alert() {
    hs.ui.alert("Task completed successfully!")
        .font(HSFont.headline())
        .duration(3)
        .padding(30)
        .show();
}

// Example 8: Dialog with buttons
function example8_dialog() {
    hs.ui.dialog("Would you like to continue?")
        .informativeText("This action will modify your settings.")
        .buttons(["Continue", "Cancel"])
        .onButton((index) => {
            if (index === 0) {
                print("User chose to continue");
                hs.ui.alert("Continuing...").show();
            } else {
                print("User cancelled");
                hs.ui.alert("Cancelled").show();
            }
        })
        .show();
}

// Example 9: Save dialog pattern
function example9_saveDialog() {
    hs.ui.dialog("Save changes?")
        .informativeText("Your document has unsaved changes.")
        .buttons(["Save", "Don't Save", "Cancel"])
        .onButton((index) => {
            if (index === 0) {
                print("Saving document...");
                hs.ui.alert("Document saved").duration(2).show();
            } else if (index === 1) {
                print("Discarding changes...");
            } else {
                print("Cancelled");
            }
        })
        .show();
}

// Example 10: Z-Stack (overlapping elements)
function example10_zstack() {
    hs.ui.window({x: 100, y: 100, w: 300, h: 300})
        .zstack()
            .padding(20)
            .rectangle()
                .fill("#FF0000")
                .opacity(0.5)
                .frame({w: 250, h: 250})
            .circle()
                .fill("#00FF00")
                .opacity(0.5)
                .frame({w: 200, h: 200})
            .rectangle()
                .fill("#0000FF")
                .opacity(0.5)
                .cornerRadius(20)
                .frame({w: 150, h: 150})
        .end()
        .backgroundColor("#FFFFFF")
        .show();
}

// Example 11: Using spacers for layout
function example11_spacers() {
    hs.ui.window({x: 100, y: 100, w: 300, h: 200})
        .vstack()
            .spacing(10)
            .padding(20)
            .text("Top Content")
                .font(HSFont.headline())
                .foregroundColor("#FFFFFF")
            .spacer()  // Pushes content apart
            .text("Bottom Content")
                .font(HSFont.headline())
                .foregroundColor("#FFFFFF")
        .end()
        .backgroundColor("#34495E")
        .show();
}

// Example 12: Spacers in horizontal layout
function example12_hspacers() {
    hs.ui.window({x: 450, y: 100, w: 400, h: 100})
        .hstack()
            .spacing(10)
            .padding(20)
            .text("Left")
                .font(HSFont.headline())
                .foregroundColor("#FFFFFF")
            .spacer()  // Pushes content to edges
            .text("Center")
                .font(HSFont.headline())
                .foregroundColor("#FFFFFF")
            .spacer()  // Another spacer
            .text("Right")
                .font(HSFont.headline())
                .foregroundColor("#FFFFFF")
        .end()
        .backgroundColor("#2C3E50")
        .show();
}

// Example 13: Text input prompt
function example13_textPrompt() {
    hs.ui.textPrompt("Enter your name")
        .informativeText("Please enter your full name below")
        .defaultText("John Doe")
        .buttons(["OK", "Cancel"])
        .onButton((buttonIndex, text) => {
            if (buttonIndex === 0) {
                print("User entered: " + text);
                hs.ui.alert("Hello, " + text + "!").show();
            } else {
                print("User cancelled");
            }
        })
        .show();
}

// Example 14: File picker
function example14_filePicker() {
    hs.ui.filePicker()
        .message("Choose a file to process")
        .canChooseFiles(true)
        .canChooseDirectories(false)
        .allowsMultipleSelection(false)
        .allowedFileTypes(["txt", "md", "js"])
        .onSelection((result) => {
            if (result) {
                print("Selected file: " + result);
                hs.ui.alert("Selected: " + result).show();
            } else {
                print("User cancelled");
            }
        })
        .show();
}

// Example 15: Directory picker with multiple selection
function example15_directoryPicker() {
    hs.ui.filePicker()
        .message("Choose directories to backup")
        .canChooseFiles(false)
        .canChooseDirectories(true)
        .allowsMultipleSelection(true)
        .onSelection((result) => {
            if (result) {
                print("Selected " + result.length + " directories:");
                for (let dir of result) {
                    print("  - " + dir);
                }
            } else {
                print("User cancelled");
            }
        })
        .show();
}

// Run all examples (uncomment to test)
// print("Running hs.ui examples...");
// example1_simpleRectangle();
// example2_circleStroke();
// example3_text();
// example4_vstack();
// example5_hstack();
// example6_nested();
// example7_alert();
// example8_dialog();
// example9_saveDialog();
// example10_zstack();
// example11_spacers();
// example12_hspacers();
// example13_textPrompt();
// example14_filePicker();
// example15_directoryPicker();
// print("Examples complete!");
