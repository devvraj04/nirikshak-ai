import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../widgets/aura_background.dart';
import '../widgets/nirikshak_app_bar.dart';

class RulesChatScreen extends StatefulWidget {
  final int initialTabIndex;
  final String? initialQuery;
  final String? quotedRuleCode;
  final String? quotedRuleTitle;
  final String? violationReason;
  final String? violationPenalty;

  const RulesChatScreen({
    super.key,
    this.initialTabIndex = 0,
    this.initialQuery,
    this.quotedRuleCode,
    this.quotedRuleTitle,
    this.violationReason,
    this.violationPenalty,
  });

  @override
  State<RulesChatScreen> createState() => _RulesChatScreenState();
}

class _RulesChatScreenState extends State<RulesChatScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  // Rules Catalog State
  List<Map<String, dynamic>> _rules = [];
  bool _loadingRules = false;
  String _ruleSearchQuery = '';
  String _selectedCategory = 'All';

  // Chatbot State
  final List<Map<String, dynamic>> _chatMessages = [];
  bool _isChatLoading = false;
  String? _activeQuotedContext;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: (widget.initialQuery != null || widget.quotedRuleCode != null) ? 1 : widget.initialTabIndex,
    );

    _loadRules();

    // Initial greeting
    _chatMessages.add({
      'isUser': false,
      'text': 'Hello! I am your **NIRIKSHAK AI Legal Counsel**.\n\n'
          'I am directly connected to the **Legal Metrology (Packaged Commodities) Act, 2009 & Rules, 2011** knowledge base.\n\n'
          'Ask me any question regarding mandatory package declarations, font heights, unit metrics, MRP compliance, dual-pricing, or statutory penalties under Section 36.',
      'citations': [],
      'timestamp': 'Just now',
    });

    // Handle deep-link redirection with violation context
    if (widget.quotedRuleCode != null || widget.initialQuery != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleInitialViolationRedirection();
      });
    }
  }

  void _handleInitialViolationRedirection() {
    final ruleCode = widget.quotedRuleCode ?? 'RULE';
    final ruleTitle = widget.quotedRuleTitle ?? 'Package Compliance';
    final reason = widget.violationReason ?? 'Declaration missing or non-compliant.';
    final penalty = widget.violationPenalty ?? '';

    final query = widget.initialQuery ??
        'Explain the legal violation for $ruleCode ($ruleTitle): "$reason". '
        'What does the Legal Metrology (Packaged Commodities) Rules mandate, and what statutory penalties apply under Section 36?';

    setState(() {
      _activeQuotedContext = '$ruleCode: $ruleTitle — Reason: $reason';
    });

    _sendUserMessage(query, ruleId: ruleCode, contextText: '$ruleCode: $ruleTitle. Reason: $reason. Penalty: $penalty');
  }

  Future<void> _loadRules() async {
    setState(() => _loadingRules = true);
    try {
      final data = await ApiClient().fetchRules();
      if (mounted) {
        setState(() {
          _rules = List<Map<String, dynamic>>.from(data);
          _loadingRules = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingRules = false);
    }
  }

  Future<void> _sendUserMessage(String message, {String? ruleId, String? contextText}) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;

    final nowStr = '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}';
    final effectiveContext = contextText ?? _activeQuotedContext;
    final quotedForBubble = _activeQuotedContext;

    setState(() {
      _chatMessages.add({
        'isUser': true,
        'text': trimmed,
        'quotedContext': quotedForBubble,
        'timestamp': nowStr,
      });
      _isChatLoading = true;
      _activeQuotedContext = null;
    });

    _chatController.clear();
    _scrollToBottom();

    try {
      final res = await ApiClient().sendChatMessage(
        trimmed,
        ruleId: ruleId,
        context: effectiveContext,
      );

      final reply = res['reply']?.toString() ?? 'No response received from RAG LLM.';
      final rawCitations = (res['citations'] as List?) ?? [];
      final citations = rawCitations.map((c) => Map<String, dynamic>.from(c as Map)).toList();

      if (mounted) {
        setState(() {
          _chatMessages.add({
            'isUser': false,
            'text': reply,
            'citations': citations,
            'timestamp': nowStr,
          });
          _isChatLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _chatMessages.add({
            'isUser': false,
            'text': '⚠️ An error occurred while communicating with the Legal Metrology AI: $e\n\nPlease check your internet connection or backend service status.',
            'citations': [],
            'timestamp': nowStr,
          });
          _isChatLoading = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _askAboutRule(Map<String, dynamic> rule) {
    final code = rule['rule_code'] ?? rule['rule_id'] ?? 'Rule';
    final title = rule['title'] ?? 'Rule';
    final act = rule['act_reference'] ?? 'LMPC Rules, 2011';

    final prompt = 'Please provide an authoritative legal breakdown of $code ($title) under the $act. '
        'What are the mandatory requirements, common non-compliance scenarios, and statutory penalties under Section 36?';

    setState(() {
      _activeQuotedContext = '$code: $title';
    });

    _tabController.animateTo(1);
    _sendUserMessage(prompt, ruleId: rule['rule_id']?.toString(), contextText: '$code: $title ($act)');
  }

  @override
  void dispose() {
    _tabController.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.auraBg,
      body: AuraBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Top App Bar
              _buildTopBar(context),

              // Segmented Tab Switcher
              _buildSegmentedTabBar(),

              // Tab View Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Rules Directory
                    _buildRulesDirectoryTab(),

                    // Tab 2: RAG Legal AI Chatbot
                    _buildChatbotTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: NirikshakAppBar(
        badgeText: 'RAG LEGAL AI',
        subtitle: 'LMPC Legal Counsel & Rules',
        showBackButton: true,
        onBack: () => Navigator.of(context).maybePop(),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.slate900,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_outlined, size: 12, color: AppTheme.emerald400),
              SizedBox(width: 4),
              Text(
                'Act 2009',
                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentedTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: AppTheme.slate900,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: AppTheme.slate600,
        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(
            iconMargin: EdgeInsets.zero,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.gavel_rounded, size: 15),
                SizedBox(width: 6),
                Flexible(child: Text('All Rules', maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          Tab(
            iconMargin: EdgeInsets.zero,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smart_toy_outlined, size: 15),
                SizedBox(width: 6),
                Flexible(child: Text('RAG Legal AI', maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 1: RULES DIRECTORY
  // ===========================================================================
  Widget _buildRulesDirectoryTab() {
    final categories = ['All', 'Pricing & Taxes', 'Weight & Measure', 'Manufacturer Identity', 'Dates & Shelf Life', 'Consumer Grievance'];

    final filteredRules = _rules.where((r) {
      final matchesSearch = _ruleSearchQuery.isEmpty ||
          (r['rule_code'] ?? '').toString().toLowerCase().contains(_ruleSearchQuery.toLowerCase()) ||
          (r['title'] ?? '').toString().toLowerCase().contains(_ruleSearchQuery.toLowerCase()) ||
          (r['description'] ?? '').toString().toLowerCase().contains(_ruleSearchQuery.toLowerCase());

      final matchesCat = _selectedCategory == 'All' || (r['category'] ?? '') == _selectedCategory;
      return matchesSearch && matchesCat;
    }).toList();

    return Column(
      children: [
        // Search & Filter Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              // Search Input
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.slate200),
                ),
                child: TextField(
                  onChanged: (val) => setState(() => _ruleSearchQuery = val),
                  style: const TextStyle(fontSize: 13, color: AppTheme.slate900),
                  decoration: InputDecoration(
                    hintText: 'Search rules by title, keyword, or number...',
                    hintStyle: const TextStyle(color: AppTheme.slate400, fontSize: 12),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppTheme.slate500),
                    suffixIcon: _ruleSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16, color: AppTheme.slate500),
                            onPressed: () => setState(() => _ruleSearchQuery = ''),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Category Pills
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: categories.map((cat) {
                    final isSel = _selectedCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedCategory = cat),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isSel ? AppTheme.emerald600 : Colors.white.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSel ? AppTheme.emerald600 : AppTheme.slate200,
                            ),
                          ),
                          child: Text(
                            cat,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
                              color: isSel ? Colors.white : AppTheme.slate700,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),

        // Rules List
        Expanded(
          child: _loadingRules
              ? const Center(child: CircularProgressIndicator(color: AppTheme.emerald600))
              : filteredRules.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.search_off_rounded, size: 40, color: AppTheme.slate400),
                          const SizedBox(height: 8),
                          Text(
                            'No rules matching "$_ruleSearchQuery"',
                            style: const TextStyle(color: AppTheme.slate500, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      itemCount: filteredRules.length,
                      itemBuilder: (context, index) {
                        final rule = filteredRules[index];
                        return _buildRuleCard(rule);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildRuleCard(Map<String, dynamic> rule) {
    final code = (rule['rule_code'] ?? rule['rule_id'] ?? 'Rule').toString();
    final title = (rule['title'] ?? 'Rule Title').toString();
    final act = (rule['act_reference'] ?? 'Legal Metrology (Packaged Commodities) Rules, 2011').toString();
    final desc = (rule['description'] ?? '').toString();
    final penalty = (rule['penalty'] ?? '').toString();
    final quote = (rule['legal_quote'] ?? '').toString();
    final severity = (rule['severity'] ?? 'CRITICAL').toString();

    final isCritical = severity.toUpperCase() == 'CRITICAL';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Badge Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.slate900,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    code,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: (isCritical ? AppTheme.dangerRed : AppTheme.warningOrange).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    severity.toUpperCase(),
                    style: TextStyle(
                      color: isCritical ? AppTheme.dangerRed : AppTheme.warningOrange,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Title & Act Reference
            Text(
              title,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: AppTheme.slate900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              act,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.slate500,
              ),
            ),

            const SizedBox(height: 8),

            // Plain Description
            Text(
              desc,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.slate700,
                height: 1.3,
              ),
            ),

            if (quote.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.gavel_rounded, size: 12, color: AppTheme.slate600),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        quote,
                        style: const TextStyle(
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                          color: Color(0xFF1E293B),
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (penalty.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 13, color: Color(0xFFB45309)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        penalty,
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF92400E),
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),

            // Ask AI Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _askAboutRule(rule),
                icon: const Icon(Icons.auto_awesome, size: 13),
                label: const Text(
                  'Ask Legal AI About This Rule',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.emerald600.withValues(alpha: 0.12),
                  foregroundColor: AppTheme.emerald700,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 2: RAG LEGAL AI CHATBOT
  // ===========================================================================
  Widget _buildChatbotTab() {
    return Column(
      children: [
        // Active Quoted Context Banner (if deep-linked or user selected a rule)
        if (_activeQuotedContext != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7), // Amber 100
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFCD34D)),
            ),
            child: Row(
              children: [
                const Icon(Icons.format_quote_rounded, size: 16, color: Color(0xFF92400E)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Active Violation Reference:\n$_activeQuotedContext',
                    style: const TextStyle(fontSize: 10.5, color: Color(0xFF78350F), fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 14, color: Color(0xFF92400E)),
                  onPressed: () => setState(() => _activeQuotedContext = null),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

        // Messages List
        Expanded(
          child: ListView.builder(
            controller: _chatScrollController,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: _chatMessages.length,
            itemBuilder: (context, index) {
              final msg = _chatMessages[index];
              return _buildMessageBubble(msg);
            },
          ),
        ),

        // Typing indicator
        if (_isChatLoading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.slate200),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.emerald600),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Searching ChromaDB & generating legal analysis...',
                        style: TextStyle(fontSize: 10.5, color: AppTheme.slate600, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Suggested Prompt Chips
        _buildSuggestedPrompts(),

        // Chat Input Bar
        _buildChatInputBar(),
      ],
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg) {
    final bool isUser = msg['isUser'] == true;
    final String text = msg['text'] ?? '';
    final String timestamp = msg['timestamp'] ?? '';
    final String? quoted = msg['quotedContext'] as String?;
    final List citations = (msg['citations'] as List?) ?? [];

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUser ? AppTheme.slate900 : Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          border: Border.all(
            color: isUser ? Colors.transparent : Colors.white.withValues(alpha: 0.9),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quoted reference snippet for user messages
            if (isUser && quoted != null && quoted.isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Ref: $quoted',
                  style: const TextStyle(color: AppTheme.emerald300, fontSize: 9.5, fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],

            // Message Body
            SelectableText(
              text,
              style: TextStyle(
                color: isUser ? Colors.white : AppTheme.slate900,
                fontSize: 12.5,
                height: 1.35,
                fontWeight: isUser ? FontWeight.w500 : FontWeight.w400,
              ),
            ),

            // Citations Box for AI response
            if (!isUser && citations.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.menu_book_rounded, size: 12, color: AppTheme.slate700),
                        SizedBox(width: 4),
                        Text(
                          'RETRIEVED STATUTORY CITATIONS (ChromaDB):',
                          style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: AppTheme.slate700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ...citations.map((c) {
                      final doc = (c['document'] ?? 'LMPC Document').toString();
                      final rule = (c['rule'] ?? '').toString();
                      final excerpt = (c['excerpt'] ?? '').toString();

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '• $doc ($rule): $excerpt',
                          style: const TextStyle(fontSize: 9, color: AppTheme.slate600, height: 1.2),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 6),

            // Timestamp & Copy Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  timestamp,
                  style: TextStyle(
                    fontSize: 8.5,
                    color: isUser ? Colors.white54 : AppTheme.slate400,
                  ),
                ),
                if (!isUser)
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Legal analysis copied to clipboard'), duration: Duration(seconds: 1)),
                      );
                    },
                    child: const Icon(Icons.copy_rounded, size: 12, color: AppTheme.slate400),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestedPrompts() {
    final prompts = [
      'What is Rule 6(1)(d) MRP mandate?',
      'Section 36 penalties for repeat offences?',
      'How to report MRP overcharging?',
      'Net Quantity metric unit rules?',
    ];

    return Container(
      height: 34,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: prompts.length,
        itemBuilder: (context, index) {
          final p = prompts[index];
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ActionChip(
              label: Text(p, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppTheme.slate700)),
              backgroundColor: Colors.white.withValues(alpha: 0.85),
              side: const BorderSide(color: AppTheme.slate200, width: 0.8),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              onPressed: () => _sendUserMessage(p),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChatInputBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        border: Border(top: BorderSide(color: AppTheme.slate200.withValues(alpha: 0.8))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_activeQuotedContext != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: AppTheme.emerald50.withValues(alpha: 0.95),
              child: Row(
                children: [
                  const Icon(Icons.format_quote_rounded, size: 14, color: AppTheme.emerald700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Context: $_activeQuotedContext',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppTheme.emerald800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _activeQuotedContext = null),
                    child: const Icon(Icons.close_rounded, size: 14, color: AppTheme.slate500),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppTheme.slate200),
                    ),
                    child: TextField(
                      controller: _chatController,
                      style: const TextStyle(fontSize: 12.5, color: AppTheme.slate900),
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Ask any question on LMPC Act & Rules...',
                        hintStyle: TextStyle(color: AppTheme.slate400, fontSize: 11.5),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (val) => _sendUserMessage(val),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _sendUserMessage(_chatController.text),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppTheme.slate900,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.slate900.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.send_rounded, size: 18, color: AppTheme.emerald400),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
