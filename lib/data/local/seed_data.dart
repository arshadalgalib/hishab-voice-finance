import '../../domain/enums.dart';

/// A built-in category, including the spoken synonyms the voice parser uses to
/// map free text onto it.
class DefaultCategory {
  const DefaultCategory({
    required this.name,
    required this.kind,
    required this.iconName,
    required this.colorValue,
    required this.keywords,
  });

  final String name;
  final CategoryKind kind;
  final String iconName;
  final int colorValue;

  /// Bengali, Banglish and English keywords.
  final List<String> keywords;
}

/// Icon keys are resolved to real [IconData] by `CategoryIcons` in the UI
/// layer. Storing a *name* instead of a code point keeps icon tree-shaking
/// working and survives icon set changes.
const int kColorFood = 0xFFEF6C00;
const int kColorGroceries = 0xFF2E7D32;
const int kColorTransport = 0xFF1565C0;
const int kColorShopping = 0xFF8E24AA;
const int kColorRent = 0xFF5D4037;
const int kColorUtilities = 0xFF00838F;
const int kColorEducation = 0xFF3949AB;
const int kColorHealthcare = 0xFFC62828;
const int kColorMobile = 0xFF6A1B9A;
const int kColorInternet = 0xFF0277BD;
const int kColorSubscription = 0xFFAD1457;
const int kColorEntertainment = 0xFFD81B60;
const int kColorTravel = 0xFF00695C;
const int kColorPersonal = 0xFFF06292;
const int kColorFamily = 0xFF7B1FA2;
const int kColorLoan = 0xFF455A64;
const int kColorFees = 0xFF757575;
const int kColorMisc = 0xFF546E7A;
const int kColorSalary = 0xFF2E7D32;
const int kColorFreelance = 0xFF00897B;
const int kColorBusiness = 0xFFF9A825;
const int kColorResearch = 0xFF4527A0;
const int kColorGift = 0xFFEC407A;
const int kColorInvestment = 0xFF00695C;
const int kColorRefund = 0xFF43A047;
const int kColorInterest = 0xFF1E88E5;

const List<DefaultCategory> kDefaultCategories = <DefaultCategory>[
  // ── expense ───────────────────────────────────────────────────────────────
  DefaultCategory(
    name: 'Food & Dining',
    kind: CategoryKind.expense,
    iconName: 'restaurant',
    colorValue: kColorFood,
    keywords: [
      'খাবার',
      'খাওয়া',
      'খেয়েছি',
      'লাঞ্চ',
      'ডিনার',
      'নাস্তা',
      'নাশতা',
      'টিফিন',
      'রেস্টুরেন্ট',
      'হোটেল খাওয়া',
      'বিরিয়ানি',
      'ভাত',
      'চা',
      'কফি',
      'বার্গার',
      'food',
      'lunch',
      'dinner',
      'breakfast',
      'snack',
      'restaurant',
      'biryani',
      'tea',
      'coffee',
    ],
  ),
  DefaultCategory(
    name: 'Groceries',
    kind: CategoryKind.expense,
    iconName: 'shopping_basket',
    colorValue: kColorGroceries,
    keywords: [
      'বাজার',
      'বাজার করেছি',
      'মুদি',
      'নিত্যপ্রয়োজনীয়',
      'সবজি',
      'চাল',
      'ডাল',
      'তেল',
      'মাছ',
      'মাংস',
      'কাঁচাবাজার',
      'grocery',
      'groceries',
      'bazar',
      'bazaar',
      'market',
      'kacha bazar',
      'vegetables',
    ],
  ),
  DefaultCategory(
    name: 'Transport',
    kind: CategoryKind.expense,
    iconName: 'directions_bus',
    colorValue: kColorTransport,
    keywords: [
      'রিকশা',
      'সিএনজি',
      'সিএনজি',
      'বাস',
      'ট্রেন',
      'লঞ্চ',
      'উবার',
      'পাঠাও',
      'ট্যাক্সি',
      'অটো',
      'যাতায়াত',
      'গাড়ি ভাড়া',
      'টিকিট',
      'transport',
      'rickshaw',
      'cng',
      'bus',
      'train',
      'launch',
      'uber',
      'pathao',
      'taxi',
      'fare',
      'ride',
      'commute',
    ],
  ),
  DefaultCategory(
    name: 'Shopping',
    kind: CategoryKind.expense,
    iconName: 'shopping_bag',
    colorValue: kColorShopping,
    keywords: [
      'কেনাকাটা',
      'কিনলাম',
      'শপিং',
      'কাপড়',
      'জুতা',
      'পোশাক',
      'মল',
      'ঘড়ি',
      'shopping',
      'shoes',
      'clothes',
      'dress',
      'mall',
      'shop',
    ],
  ),
  DefaultCategory(
    name: 'House Rent',
    kind: CategoryKind.expense,
    iconName: 'home',
    colorValue: kColorRent,
    keywords: [
      'বাসা ভাড়া',
      'ঘর ভাড়া',
      'অফিস ভাড়া',
      'বাসাভাড়া',
      'house rent',
      'rent',
      'office rent',
    ],
  ),
  DefaultCategory(
    name: 'Utilities',
    kind: CategoryKind.expense,
    iconName: 'bolt',
    colorValue: kColorUtilities,
    keywords: [
      'বিদ্যুৎ',
      'কারেন্ট',
      'কারেন্ট বিল',
      'বিদ্যুৎ বিল',
      'গ্যাস',
      'গ্যাস বিল',
      'পানি',
      'পানির বিল',
      'ওয়াসা',
      'ডেসকো',
      'utility',
      'utilities',
      'electricity',
      'gas bill',
      'water bill',
      'wasa',
      'desco',
    ],
  ),
  DefaultCategory(
    name: 'Education',
    kind: CategoryKind.expense,
    iconName: 'school',
    colorValue: kColorEducation,
    keywords: [
      'পড়াশোনা',
      'বই',
      'টিউশন',
      'কোচিং',
      'স্কুল',
      'কলেজ',
      'বিশ্ববিদ্যালয়',
      'পরীক্ষার ফি',
      'শিক্ষা',
      'tuition',
      'book',
      'school',
      'college',
      'university',
      'education',
      'exam fee',
    ],
  ),
  DefaultCategory(
    name: 'Healthcare',
    kind: CategoryKind.expense,
    iconName: 'medical_services',
    colorValue: kColorHealthcare,
    keywords: [
      'ঔষধ',
      'ওষুধ',
      'ডাক্তার',
      'হাসপাতাল',
      'চিকিৎসা',
      'মেডিসিন',
      'টেস্ট',
      'ডাক্তার দেখানো',
      'medicine',
      'doctor',
      'hospital',
      'health',
      'healthcare',
      'treatment',
      'clinic',
      'pharmacy',
    ],
  ),
  DefaultCategory(
    name: 'Mobile Recharge',
    kind: CategoryKind.expense,
    iconName: 'smartphone',
    colorValue: kColorMobile,
    keywords: [
      'রিচার্জ',
      'মোবাইল রিচার্জ',
      'টপ আপ',
      'টপ-আপ',
      'সিম',
      'মোবাইল ব্যালেন্স',
      'recharge',
      'topup',
      'top up',
      'mobile recharge',
      'sim',
    ],
  ),
  DefaultCategory(
    name: 'Internet',
    kind: CategoryKind.expense,
    iconName: 'wifi',
    colorValue: kColorInternet,
    keywords: [
      'ইন্টারনেট',
      'ব্রডব্যান্ড',
      'ওয়াইফাই',
      'ওয়াই-ফাই',
      'ডাটা প্যাক',
      'internet',
      'broadband',
      'wifi',
      'wi-fi',
      'data pack',
    ],
  ),
  DefaultCategory(
    name: 'Subscriptions',
    kind: CategoryKind.expense,
    iconName: 'subscriptions',
    colorValue: kColorSubscription,
    keywords: [
      'সাবস্ক্রিপশন',
      'নেটফ্লিক্স',
      'স্পটিফাই',
      'ইউটিউব প্রিমিয়াম',
      'প্রাইম',
      'subscription',
      'netflix',
      'spotify',
      'youtube premium',
      'prime',
      'chatgpt',
    ],
  ),
  DefaultCategory(
    name: 'Entertainment',
    kind: CategoryKind.expense,
    iconName: 'movie',
    colorValue: kColorEntertainment,
    keywords: [
      'সিনেমা',
      'মুভি',
      'গেম',
      'বিনোদন',
      'কনসার্ট',
      'ঘুরতে',
      'cinema',
      'movie',
      'game',
      'entertainment',
      'concert',
    ],
  ),
  DefaultCategory(
    name: 'Travel',
    kind: CategoryKind.expense,
    iconName: 'flight',
    colorValue: kColorTravel,
    keywords: [
      'ভ্রমণ',
      'ট্যুর',
      'হোটেল',
      'ফ্লাইট',
      'ট্রেনের টিকিট',
      'বেড়াতে',
      'travel',
      'tour',
      'hotel',
      'flight',
      'trip',
      'vacation',
    ],
  ),
  DefaultCategory(
    name: 'Personal Care',
    kind: CategoryKind.expense,
    iconName: 'spa',
    colorValue: kColorPersonal,
    keywords: [
      'পার্লার',
      'সেলুন',
      'হেয়ারকাট',
      'চুল কাটা',
      'কসমেটিকস',
      'personal care',
      'salon',
      'parlor',
      'haircut',
      'cosmetics',
    ],
  ),
  DefaultCategory(
    name: 'Family & Gifts',
    kind: CategoryKind.expense,
    iconName: 'volunteer_activism',
    colorValue: kColorFamily,
    keywords: [
      'উপহার',
      'গিফট',
      'দান',
      'পরিবার',
      'জানানো',
      'gift',
      'family',
      'donation',
      'charity',
    ],
  ),
  DefaultCategory(
    name: 'Loan Repayment',
    kind: CategoryKind.expense,
    iconName: 'request_quote',
    colorValue: kColorLoan,
    keywords: [
      'ঋণ',
      'ঋণ পরিশোধ',
      'কিস্তি',
      'ধার পরিশোধ',
      'লোন',
      'loan',
      'emi',
      'installment',
      'repayment',
      'debt',
    ],
  ),
  DefaultCategory(
    name: 'Fees & Charges',
    kind: CategoryKind.expense,
    iconName: 'receipt_long',
    colorValue: kColorFees,
    keywords: [
      'চার্জ',
      'ফি',
      'সার্ভিস চার্জ',
      'ফি কাটা',
      'কমিশন',
      'fee',
      'fees',
      'charge',
      'service charge',
      'commission',
      'cash out charge',
    ],
  ),
  DefaultCategory(
    name: 'Miscellaneous',
    kind: CategoryKind.expense,
    iconName: 'category',
    colorValue: kColorMisc,
    keywords: [
      'অন্যান্য',
      'মিসলেনিয়াস',
      'বিবিধ',
      'misc',
      'miscellaneous',
      'other',
    ],
  ),

  // ── income ────────────────────────────────────────────────────────────────
  DefaultCategory(
    name: 'Salary',
    kind: CategoryKind.income,
    iconName: 'payments',
    colorValue: kColorSalary,
    keywords: [
      'বেতন',
      'স্যালারি',
      'মাইনে',
      'বোনাস',
      'salary',
      'wage',
      'payroll',
      'bonus',
      'মাসিক বেতন',
    ],
  ),
  DefaultCategory(
    name: 'Freelancing',
    kind: CategoryKind.income,
    iconName: 'laptop',
    colorValue: kColorFreelance,
    keywords: [
      'ফ্রিল্যান্স',
      'ফ্রিল্যান্সিং',
      'আপওয়ার্ক',
      'ফাইভার',
      'ক্লায়েন্ট পেমেন্ট',
      'freelance',
      'freelancing',
      'upwork',
      'fiverr',
      'client payment',
    ],
  ),
  DefaultCategory(
    name: 'Business',
    kind: CategoryKind.income,
    iconName: 'storefront',
    colorValue: kColorBusiness,
    keywords: [
      'ব্যবসা',
      'বিক্রি',
      'দোকান',
      'লাভ',
      'profit',
      'business',
      'sales',
      'shop income',
    ],
  ),
  DefaultCategory(
    name: 'Research & Projects',
    kind: CategoryKind.income,
    iconName: 'science',
    colorValue: kColorResearch,
    keywords: [
      'গবেষণা',
      'প্রকল্প',
      'প্রজেক্ট',
      'রিসার্চ',
      'অনুদান',
      'সম্মানী',
      'research',
      'project',
      'grant',
      'honorarium',
      'stipend',
    ],
  ),
  DefaultCategory(
    name: 'Gifts Received',
    kind: CategoryKind.income,
    iconName: 'card_giftcard',
    colorValue: kColorGift,
    keywords: [
      'উপহার',
      'গিফট',
      'ঈদি',
      'সালামি',
      'gift',
      'eidi',
      'salami',
      'gift received',
    ],
  ),
  DefaultCategory(
    name: 'Investment Returns',
    kind: CategoryKind.income,
    iconName: 'trending_up',
    colorValue: kColorInvestment,
    keywords: [
      'বিনিয়োগ',
      'লভ্যাংশ',
      'ডিভিডেন্ড',
      'মুনাফা',
      'স্টক',
      'investment',
      'dividend',
      'return',
      'stock',
      'mutual fund',
    ],
  ),
  DefaultCategory(
    name: 'Refunds',
    kind: CategoryKind.income,
    iconName: 'replay',
    colorValue: kColorRefund,
    keywords: [
      'ফেরত',
      'রিফান্ড',
      'ক্যাশব্যাক',
      'ফেরত পেয়েছি',
      'refund',
      'cashback',
      'reimbursement',
    ],
  ),
  DefaultCategory(
    name: 'Rental Income',
    kind: CategoryKind.income,
    iconName: 'apartment',
    colorValue: kColorRent,
    keywords: [
      'বাসা ভাড়া পেয়েছি',
      'ভাড়া পেয়েছি',
      'rent received',
      'rental income',
    ],
  ),
  DefaultCategory(
    name: 'Interest',
    kind: CategoryKind.income,
    iconName: 'account_balance',
    colorValue: kColorInterest,
    keywords: ['সুদ', 'ব্যাংক সুদ', 'interest', 'bank interest'],
  ),
  DefaultCategory(
    name: 'Other Income',
    kind: CategoryKind.income,
    iconName: 'savings',
    colorValue: kColorMisc,
    keywords: [
      'অন্যান্য আয়',
      'পাওনা',
      'আয়',
      'other income',
      'misc income',
      'received',
    ],
  ),
];

/// Quick-add wallets offered during onboarding.
class DefaultWalletTemplate {
  const DefaultWalletTemplate({
    required this.name,
    required this.type,
    this.institution,
    this.emoji,
  });

  final String name;
  final WalletType type;
  final String? institution;
  final String? emoji;
}

const List<DefaultWalletTemplate> kDefaultWalletTemplates =
    <DefaultWalletTemplate>[
      DefaultWalletTemplate(name: 'Cash', type: WalletType.cash, emoji: '💵'),
      DefaultWalletTemplate(
        name: 'bKash',
        type: WalletType.bkash,
        institution: 'bKash',
      ),
      DefaultWalletTemplate(
        name: 'Nagad',
        type: WalletType.nagad,
        institution: 'Nagad',
      ),
      DefaultWalletTemplate(
        name: 'Rocket',
        type: WalletType.rocket,
        institution: 'Rocket',
      ),
      DefaultWalletTemplate(
        name: 'Bank Account',
        type: WalletType.bank,
        emoji: '🏦',
      ),
      DefaultWalletTemplate(
        name: 'Savings',
        type: WalletType.savings,
        emoji: '🎯',
      ),
    ];
