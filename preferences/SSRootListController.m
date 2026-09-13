#import <Preferences/PSListController.h>
#import <Preferences/PSTableCell.h>
#import "../SSPreferences.h"

@interface SSSpeedCell : PSTableCell <UITextFieldDelegate>
@property (nonatomic, strong) UISlider *speedSlider;
@property (nonatomic, strong) UITextField *speedField;
@property (nonatomic, strong) NSNumberFormatter *speedFormatter;
@property (nonatomic) double savedSpeed;
@end

@implementation SSSpeedCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
    if (!self) return nil;

    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.textLabel.text = nil;

    self.speedFormatter = [[NSNumberFormatter alloc] init];
    self.speedFormatter.locale = [NSLocale currentLocale];
    self.speedFormatter.numberStyle = NSNumberFormatterDecimalStyle;
    self.speedFormatter.usesGroupingSeparator = NO;
    self.speedFormatter.minimumFractionDigits = 2;
    self.speedFormatter.maximumFractionDigits = 2;

    self.speedSlider = [[UISlider alloc] init];
    self.speedSlider.minimumValue = SS_SPEED_MIN;
    self.speedSlider.maximumValue = SS_SPEED_MAX;
    self.speedSlider.accessibilityLabel = @"Swipe speed";
    self.speedSlider.accessibilityHint = @"Higher values move the cursor faster.";
    [self.speedSlider addTarget:self action:@selector(sliderChanged:)
               forControlEvents:UIControlEventValueChanged];

    self.speedField = [[UITextField alloc] init];
    self.speedField.borderStyle = UITextBorderStyleRoundedRect;
    self.speedField.textAlignment = NSTextAlignmentCenter;
    self.speedField.keyboardType = UIKeyboardTypeDecimalPad;
    self.speedField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.speedField.delegate = self;
    self.speedField.font = [UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightRegular];
    self.speedField.adjustsFontSizeToFitWidth = YES;
    self.speedField.minimumFontSize = 12;
    self.speedField.accessibilityLabel = @"Swipe speed multiplier";
    self.speedField.accessibilityHint = [NSString stringWithFormat:
        @"Enter a number from %.2f to %.2f. The default is %.2f.",
        SS_SPEED_MIN, SS_SPEED_MAX, SS_SPEED_DEFAULT];
    [self.speedField addTarget:self action:@selector(textChanged:)
              forControlEvents:UIControlEventEditingChanged];

    // Decimal keyboards have no Return key, so provide a standard Done action.
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    toolbar.items = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                    target:nil action:nil],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                    target:self action:@selector(finishEditing)]
    ];
    self.speedField.inputAccessoryView = toolbar;

    for (UIView *control in @[self.speedSlider, self.speedField]) {
        control.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:control];
    }
    [NSLayoutConstraint activateConstraints:@[
        [self.speedSlider.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
        [self.speedSlider.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.speedSlider.trailingAnchor constraintEqualToAnchor:self.speedField.leadingAnchor constant:-16],
        [self.speedField.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
        [self.speedField.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.speedField.widthAnchor constraintEqualToConstant:84],
        [self.speedField.heightAnchor constraintEqualToConstant:36]
    ]];
    SSPublishSavedSpeed();
    self.savedSpeed = SSReadSpeed();
    [self displaySpeed:self.savedSpeed updateText:YES];
    return self;
}

- (void)displaySpeed:(double)speed updateText:(BOOL)updateText {
    self.speedSlider.value = speed;
    self.speedSlider.accessibilityValue = [NSString stringWithFormat:@"%@ times",
                                           [self.speedFormatter stringFromNumber:@(speed)]];
    if (updateText) self.speedField.text = [self.speedFormatter stringFromNumber:@(speed)];
}

- (void)saveSpeed:(double)speed updateText:(BOOL)updateText {
    speed = SSNormalizeSpeed(speed);
    if (speed == self.savedSpeed || SSWriteSpeed(speed)) {
        self.savedSpeed = speed;
        [self displaySpeed:speed updateText:updateText];
    } else {
        [self displaySpeed:self.savedSpeed updateText:YES];
    }
}

- (BOOL)parseSpeed:(NSString *)text value:(double *)value {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    // Accept both dot and comma decimal input, but never partial numeric parses
    // such as "2abc", exponents, NaN, or a grouping separator.
    NSString *normalized = [trimmed stringByReplacingOccurrencesOfString:@"," withString:@"."];
    NSRange match = [normalized rangeOfString:@"^(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)$"
                                      options:NSRegularExpressionSearch];
    if (normalized.length == 0 || match.location != 0 || match.length != normalized.length)
        return NO;
    double speed = normalized.doubleValue;
    if (!isfinite(speed)) return NO;
    *value = speed;
    return YES;
}

- (void)sliderChanged:(UISlider *)slider {
    // Capture before ending a text edit, which may refresh the slider itself.
    double speed = round(slider.value * 20.0) / 20.0;
    [self.speedField resignFirstResponder];
    [self saveSpeed:speed updateText:YES];
}

- (void)textChanged:(UITextField *)field {
    double speed;
    if ([self parseSpeed:field.text value:&speed] &&
        speed >= SS_SPEED_MIN && speed <= SS_SPEED_MAX) {
        // Preserve the user's in-progress text and cursor position.
        [self saveSpeed:speed updateText:NO];
    }
}

- (void)textFieldDidEndEditing:(UITextField *)field {
    double speed;
    if ([self parseSpeed:field.text value:&speed]) {
        [self saveSpeed:speed updateText:YES];
    } else {
        [self displaySpeed:self.savedSpeed updateText:YES];
    }
}

- (void)finishEditing {
    [self.speedField resignFirstResponder];
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    self.textLabel.text = nil;
    if (!self.speedField.isFirstResponder) {
        self.savedSpeed = SSReadSpeed();
        [self displaySpeed:self.savedSpeed updateText:YES];
    }
}

@end

@interface SSRootListController : PSListController
@end

@implementation SSRootListController

- (NSMutableArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

- (void)viewWillDisappear:(BOOL)animated {
    [self.view endEditing:YES];
    [super viewWillDisappear:animated];
}

@end
