#import <objc/Object.h>

@interface PrefsController:Object

{
	id prefsPanel;
	id switchView;
	id promptSwitch;	// switchbutton outlet
				// to control quit prompt
	id truncateSwitch;	// switchbutton outlet
				// to control truncation
	id popUpButton;		// trigger button for popuplist
}

+ initialize;
- awakeFromNib;
- displayPrefsPanel:sender;
- setTruncate:sender;
- (BOOL)shouldTruncate;
- displayPrefsPanel:sender;
- showAccessoryView:sender;

@end
