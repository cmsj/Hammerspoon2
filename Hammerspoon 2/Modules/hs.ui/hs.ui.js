// hs.ui JavaScript extensions
//
// This file provides JavaScript-side enhancements for the hs.ui module

// ---------------------------------------------------------------
// MARK: - Examples
// ---------------------------------------------------------------

/**
 * Collection of examples demonstrating hs.ui capabilities
 *
 * Usage:
 *   hs.ui.examples.simpleRectangle()
 *   hs.ui.examples.list()  // List all available examples
 */
hs.ui.examples = {
    /**
     * List all available examples
     */
    list: function() {
        print("Available hs.ui examples:");
        const examples = Object.keys(hs.ui.examples).filter(k => k !== 'list');
        examples.forEach((name, i) => {
            print(`  ${i + 1}. ${name}`);
        });
        print("\nRun with: hs.ui.examples.<name>()");
    },

    /**
     * Example 1: Simple colored rectangle
     */
    simpleRectangle: function() {
        hs.ui.window({x: 100, y: 100, w: 200, h: 200})
            .rectangle()
                .fill("#FF0000")
                .frame({w: "100%", h: "100%"})
            .show();
    },

    /**
     * Example 2: Circle with stroke
     */
    circleStroke: function() {
        hs.ui.window({x: 350, y: 100, w: 200, h: 200})
            .circle()
                .stroke("#0000FF")
                .strokeWidth(5)
                .frame({w: 150, h: 150})
            .backgroundColor("#FFFFFF")
            .show();
    },

    /**
     * Example 3: Text element
     */
    text: function() {
        hs.ui.window({x: 600, y: 100, w: 300, h: 150})
            .text("Hello, Hammerspoon!")
                .font(HSFont.title())
                .foregroundColor("#FFFFFF")
            .backgroundColor("#000000")
            .show();
    },

    /**
     * Example 4: Vertical stack layout
     */
    vstack: function() {
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
    },

    /**
     * Example 5: Horizontal stack layout
     */
    hstack: function() {
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
    },

    /**
     * Example 6: Complex nested layout
     */
    nested: function() {
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
    },

    /**
     * Example 7: Simple alert
     */
    alert: function() {
        hs.ui.alert("Task completed successfully!")
            .font(HSFont.headline())
            .duration(3)
            .padding(30)
            .show();
    },

    /**
     * Example 8: Dialog with buttons
     */
    dialog: function() {
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
    },

    /**
     * Example 9: Save dialog pattern
     */
    saveDialog: function() {
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
    },

    /**
     * Example 10: Z-Stack (overlapping elements)
     */
    zstack: function() {
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
    },

    /**
     * Example 11: Using spacers for layout
     */
    spacers: function() {
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
    },

    /**
     * Example 12: Spacers in horizontal layout
     */
    hspacers: function() {
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
    },

    /**
     * Example 13: Text input prompt
     */
    textPrompt: function() {
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
    },

    /**
     * Example 14: File picker
     */
    filePicker: function() {
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
    },

    /**
     * Example 15: Directory picker with multiple selection
     */
    directoryPicker: function() {
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
    },

    /**
     * Example 16: Display an image from a file
     */
    imageFromFile: function() {
        const img = HSImage.fromPath("~/Pictures/sample.jpg");
        if (img) {
            hs.ui.window({x: 100, y: 100, w: 600, h: 500})
                .vstack()
                    .padding(20)
                    .text("Image Viewer")
                        .font(HSFont.title())
                        .foregroundColor("#FFFFFF")
                    .image(img)
                        .resizable()
                        .aspectRatio("fit")
                        .frame({w: 560, h: 400})
                .end()
                .backgroundColor("#2C3E50")
                .show();
        } else {
            print("Failed to load image. Make sure ~/Pictures/sample.jpg exists.");
        }
    },

    /**
     * Example 17: Display system icons
     */
    systemIcons: function() {
        const icons = [
            HSImage.fromName("NSComputer"),
            HSImage.fromName("NSFolder"),
            HSImage.fromName("NSNetwork"),
            HSImage.fromName("NSTrashFull")
        ];

        const win = hs.ui.window({x: 100, y: 100, w: 400, h: 120})
            .hstack()
                .spacing(20)
                .padding(20);

        for (let icon of icons) {
            if (icon) {
                win.image(icon)
                    .resizable()
                    .frame({w: 64, h: 64});
            }
        }

        win.end()
            .backgroundColor("#F0F0F0")
            .show();
    },

    /**
     * Example 18: Display app icons
     */
    appIcons: function() {
        const apps = [
            "com.apple.Safari",
            "com.apple.finder",
            "com.apple.Terminal",
            "com.apple.iTunes"
        ];

        const win = hs.ui.window({x: 100, y: 100, w: 300, h: 300})
            .vstack()
                .spacing(15)
                .padding(20)
                .text("Application Icons")
                    .font(HSFont.headline())
                    .foregroundColor("#333333");

        for (let bundleID of apps) {
            const icon = HSImage.fromAppBundle(bundleID);
            if (icon) {
                win.hstack()
                        .spacing(10)
                        .image(icon)
                            .resizable()
                            .frame({w: 48, h: 48})
                        .text(bundleID)
                            .font(HSFont.body())
                            .foregroundColor("#666666")
                    .end();
            }
        }

        win.end()
            .backgroundColor("#FFFFFF")
            .show();
    },

    /**
     * Example 19: Load image from URL (using Promises)
     */
    imageFromURL: function() {
        const placeholderWin = hs.ui.window({x: 100, y: 100, w: 400, h: 300})
            .vstack()
                .padding(20)
                .text("Loading image from URL...")
                    .font(HSFont.title())
                    .foregroundColor("#FFFFFF")
            .end()
            .backgroundColor("#2C3E50")
            .show();

        HSImage.fromURL("https://picsum.photos/400/300")
            .then(image => {
                placeholderWin.close();

                hs.ui.window({x: 100, y: 100, w: 440, h: 360})
                    .vstack()
                        .padding(20)
                        .text("Image from URL")
                            .font(HSFont.title())
                            .foregroundColor("#FFFFFF")
                        .image(image)
                            .resizable()
                            .aspectRatio("fit")
                            .frame({w: 400, h: 300})
                    .end()
                    .backgroundColor("#2C3E50")
                    .show();
            })
            .catch(err => {
                placeholderWin.close();
                print("Failed to load image from URL:", err);
            });
    },

    /**
     * Example 20: Image manipulation
     */
    imageManipulation: function() {
        const original = HSImage.fromName("NSComputer");
        if (!original) {
            print("Failed to load image");
            return;
        }

        // Get size
        const size = original.size();
        print("Original size: " + size.w + "x" + size.h);

        // Resize
        const resized = original.setSize({w: 128, h: 128}, false);

        // Display both
        hs.ui.window({x: 100, y: 100, w: 350, h: 200})
            .hstack()
                .spacing(20)
                .padding(20)
                .vstack()
                    .spacing(5)
                    .text("Original")
                        .font(HSFont.caption())
                    .image(original)
                        .resizable()
                        .frame({w: 128, h: 128})
                .end()
                .vstack()
                    .spacing(5)
                    .text("Resized")
                        .font(HSFont.caption())
                    .image(resized)
                        .resizable()
                        .frame({w: 128, h: 128})
                .end()
            .end()
            .backgroundColor("#F5F5F5")
            .show();
    },

    /**
     * Example 21: Image with opacity
     */
    imageOpacity: function() {
        const img = HSImage.fromName("NSFolder");
        if (!img) {
            print("Failed to load image");
            return;
        }

        // Display same image at different opacities
        hs.ui.window({x: 100, y: 100, w: 450, h: 180})
            .hstack()
                .spacing(15)
                .padding(20)
                .vstack()
                    .spacing(5)
                    .text("100%")
                        .font(HSFont.caption())
                    .image(img)
                        .resizable()
                        .frame({w: 96, h: 96})
                        .opacity(1.0)
                .end()
                .vstack()
                    .spacing(5)
                    .text("75%")
                        .font(HSFont.caption())
                    .image(img)
                        .resizable()
                        .frame({w: 96, h: 96})
                        .opacity(0.75)
                .end()
                .vstack()
                    .spacing(5)
                    .text("50%")
                        .font(HSFont.caption())
                    .image(img)
                        .resizable()
                        .frame({w: 96, h: 96})
                        .opacity(0.5)
                .end()
                .vstack()
                    .spacing(5)
                    .text("25%")
                        .font(HSFont.caption())
                    .image(img)
                        .resizable()
                        .frame({w: 96, h: 96})
                        .opacity(0.25)
                .end()
            .end()
            .backgroundColor("#F5F5F5")
            .show();
    }
};

// Module is ready
console.log("hs.ui module loaded with " + (Object.keys(hs.ui.examples).length - 1) + " examples");
console.log("Run hs.ui.examples.list() to see all available examples");
