import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../themes/app_theme.dart';
import 'add_task_screen.dart';

class MemoDetailScreen extends StatefulWidget {
  final String memoId;
  final String title;
  final String body;
  final bool isCreating;

  const MemoDetailScreen({
    super.key,
    this.memoId = '',
    this.title = '',
    this.body = '',
    this.isCreating = false,
  });

  @override
  State<MemoDetailScreen> createState() => _MemoDetailScreenState();
}

class _MemoDetailScreenState extends State<MemoDetailScreen> {
  static const int _maxTitleLength = 30;
  static const int _generatedTitleLength = 20;
  static const _background = AppTheme.pageBackground;
  static const _primaryColor = Color(0xFF0F172A);
  static const _cardBorder = Color.fromRGBO(250, 198, 56, 0.05);
  static const _bodyText = Color(0xFF334155);
  static const _bodyStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: _bodyText,
    height: 1.6,
  );
  static const double _minDetailBodyHeight = 112;
  static const double _maxDetailBodyHeight = 560;
  static const double _bottomActionButtonHeight = 44;
  static const double _bottomActionBottomOffset = 20;
  static const double _bottomActionTopGap = 18;

  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late final FocusNode _titleFocusNode;
  late final FocusNode _bodyFocusNode;
  late final ScrollController _bodyScrollController;

  late String _originalTitle;
  late String _originalBody;
  late bool _isCreatingMode;
  late String _currentMemoId;
  Timer? _autosaveTimer;
  bool _isSaving = false;
  bool _isAnalyzingTask = false;
  bool _isDeleting = false;
  bool _isDiscardingOrDeleted = false;

  bool get _hasChanges {
    return _titleController.text.trim() != _originalTitle.trim() ||
        _bodyController.text.trim() != _originalBody.trim();
  }

  @override
  void initState() {
    super.initState();
    final initialTitle = widget.isCreating && widget.title.trim().isEmpty
        ? _autoTitle(DateTime.now())
        : widget.title;
    _originalTitle = initialTitle;
    _originalBody = widget.body;
    _isCreatingMode = widget.isCreating;
    _currentMemoId = widget.memoId;
    _titleController = TextEditingController(text: initialTitle)
      ..addListener(_handleFieldChanged);
    _bodyController = TextEditingController(text: widget.body)
      ..addListener(_handleBodyChanged);
    _titleFocusNode = FocusNode()..addListener(_handleFocusChange);
    _bodyFocusNode = FocusNode()..addListener(_handleFocusChange);
    _bodyScrollController = ScrollController();
  }

  void _handleFieldChanged() {
    if (!mounted) {
      return;
    }
    _scheduleAutosave();
    setState(() {});
  }

  void _handleBodyChanged() {
    if (!mounted) {
      return;
    }

    _scheduleBodyScrollToLatest();
    _scheduleAutosave();
    setState(() {});
  }

  void _handleFocusChange() {
    if (!mounted) {
      return;
    }

    if (_bodyFocusNode.hasFocus) {
      _scheduleBodyScrollToLatest();
    }
  }

  void _scheduleBodyScrollToLatest({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_bodyScrollController.hasClients) {
        return;
      }

      final selection = _bodyController.selection;
      final caretNearEnd =
          !selection.isValid ||
          selection.extentOffset >= _bodyController.text.length - 1;

      if (!force && !_bodyFocusNode.hasFocus) {
        return;
      }

      if (!force && !caretNearEnd) {
        return;
      }

      _bodyScrollController.jumpTo(
        _bodyScrollController.position.maxScrollExtent,
      );
    });
  }

  Future<_SavedMemo?> _saveMemo({
    bool popAfterCreate = false,
    bool showSuccessMessage = false,
  }) async {
    if (_isDiscardingOrDeleted) {
      return null;
    }

    final user = FirebaseAuth.instance.currentUser;
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    if (user == null) {
      _showMessage('Please sign in to save your note.');
      return null;
    }

    if (title.isEmpty && body.isEmpty) {
      _showMessage('Please enter your note first.');
      return null;
    }

    if (title.length > _maxTitleLength) {
      _showMessage('Note title cannot exceed $_maxTitleLength characters.');
      return null;
    }

    final effectiveTitle = title.isNotEmpty
        ? title
        : (_isCreatingMode ? _autoTitle(DateTime.now()) : _fallbackTitle(body));

    setState(() {
      _isSaving = true;
    });

    try {
      if (_isCreatingMode) {
        final docRef = await FirebaseFirestore.instance
            .collection('memos')
            .add({
              'userId': user.uid,
              'title': effectiveTitle,
              'body': body,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });

        _originalTitle = effectiveTitle;
        _originalBody = body;
        _currentMemoId = docRef.id;

        if (_titleController.text.trim().isEmpty) {
          _titleController.text = effectiveTitle;
          _titleController.selection = TextSelection.collapsed(
            offset: _titleController.text.length,
          );
        }

        if (!mounted) {
          return _SavedMemo(
            memoId: docRef.id,
            title: effectiveTitle,
            body: body,
          );
        }

        setState(() {
          _isCreatingMode = false;
        });

        if (popAfterCreate) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text('Note saved.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
        } else if (showSuccessMessage) {
          _showMessage('Note saved.');
        }

        return _SavedMemo(memoId: docRef.id, title: effectiveTitle, body: body);
      }

      if (_currentMemoId.isEmpty) {
        throw StateError('Missing memo id.');
      }

      await FirebaseFirestore.instance
          .collection('memos')
          .doc(_currentMemoId)
          .update({
            'title': effectiveTitle,
            'body': body,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      _originalTitle = effectiveTitle;
      _originalBody = body;

      if (!mounted) {
        return _SavedMemo(
          memoId: _currentMemoId,
          title: effectiveTitle,
          body: body,
        );
      }

      if (showSuccessMessage) {
        _showMessage('Note updated.');
      }

      return _SavedMemo(
        memoId: _currentMemoId,
        title: effectiveTitle,
        body: body,
      );
    } catch (_) {
      _showMessage('Failed to save note. Please try again.');
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();

    if (_isSaving || _isAnalyzingTask || _isDiscardingOrDeleted) {
      return;
    }

    if (!_hasChanges || !_hasSavableContent) {
      return;
    }

    _autosaveTimer = Timer(const Duration(milliseconds: 700), () {
      _flushAutosave();
    });
  }

  bool get _hasSavableContent {
    return _titleController.text.trim().isNotEmpty ||
        _bodyController.text.trim().isNotEmpty;
  }

  Future<void> _flushAutosave() async {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;

    if (_isSaving ||
        _isAnalyzingTask ||
        _isDiscardingOrDeleted ||
        !_hasChanges ||
        !_hasSavableContent) {
      return;
    }

    await _saveMemo(popAfterCreate: false, showSuccessMessage: false);
  }

  void _dismissKeyboard() {
    final currentFocus = FocusScope.of(context);
    if (!currentFocus.hasPrimaryFocus && currentFocus.focusedChild != null) {
      currentFocus.unfocus();
    }
  }

  Future<void> _handleBackNavigation() async {
    _dismissKeyboard();
    if (_isDiscardingOrDeleted) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    await _flushAutosave();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  String _fallbackTitle(String body) {
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty) {
      return 'Untitled Note';
    }

    final firstLine = trimmedBody.split('\n').first.trim();
    if (firstLine.length <= _generatedTitleLength) {
      return firstLine;
    }
    return firstLine.substring(0, _generatedTitleLength).trimRight();
  }

  String _autoTitle(DateTime createdAt) {
    final local = createdAt.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _analyzeMemoAndOpenTask() async {
    if (_isSaving || _isAnalyzingTask || _isDeleting) {
      return;
    }

    final savedMemo = (_isCreatingMode || _hasChanges)
        ? await _saveMemo(popAfterCreate: false, showSuccessMessage: false)
        : _SavedMemo(
            memoId: _currentMemoId,
            title: _originalTitle,
            body: _originalBody,
          );

    if (savedMemo == null) {
      return;
    }

    final memoTitle = savedMemo.title.trim();
    final memoBody = savedMemo.body.trim();

    if (memoTitle.isEmpty && memoBody.isEmpty) {
      _showMessage('This note is empty.');
      return;
    }

    if (memoBody.isEmpty) {
      _showMessage('Detail cannot be empty.');
      return;
    }

    setState(() {
      _isAnalyzingTask = true;
    });

    try {
      final callable =
          FirebaseFunctions.instanceFor(
            region: 'australia-southeast1',
          ).httpsCallable(
            'analyzeMemoToTask',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
          );

      final result = await callable
          .call(<String, dynamic>{
            'title': memoTitle,
            'body': memoBody,
            'timezone': DateTime.now().timeZoneName,
            'currentDateISO': _currentDateISO(),
          })
          .timeout(const Duration(seconds: 15));

      final data = Map<String, dynamic>.from(result.data as Map);
      final draft = _MemoTaskDraft.fromMap(data);

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AddTaskScreen(
            initialTitle: draft.title.isNotEmpty ? draft.title : memoTitle,
            initialNotes: draft.notes.isNotEmpty ? draft.notes : memoBody,
            initialDate: draft.date,
            initialTime: draft.time,
            initialCategory: draft.category,
          ),
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      debugPrint(
        'analyzeMemoToTask failed: code=${error.code}, '
        'message=${error.message}, details=${error.details}',
      );
      await _openManualTaskFallback(memoTitle: memoTitle, memoBody: memoBody);
    } on TimeoutException catch (error) {
      debugPrint('analyzeMemoToTask timed out: $error');
      await _openManualTaskFallback(memoTitle: memoTitle, memoBody: memoBody);
    } catch (error) {
      debugPrint('analyzeMemoToTask unexpected error: $error');
      await _openManualTaskFallback(memoTitle: memoTitle, memoBody: memoBody);
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzingTask = false;
        });
      }
    }
  }

  Future<void> _openManualTaskFallback({
    required String memoTitle,
    required String memoBody,
  }) async {
    if (!mounted) {
      return;
    }

    _showMessage(
      'No task details were detected. You can fill them in manually.',
    );

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddTaskScreen(
          initialTitle: memoTitle.isNotEmpty ? memoTitle : null,
          initialNotes: memoBody.isNotEmpty ? memoBody : null,
        ),
      ),
    );
  }

  String _currentDateISO() {
    final now = DateTime.now();
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<void> _confirmAndDeleteMemo() async {
    if (_isDeleting ||
        _isSaving ||
        _isAnalyzingTask ||
        _isDiscardingOrDeleted) {
      return;
    }

    if (_isCreatingMode || _currentMemoId.isEmpty) {
      _dismissKeyboard();
      _autosaveTimer?.cancel();
      _isDiscardingOrDeleted = true;
      Navigator.of(context).pop();
      return;
    }

    final confirmed = await _showDeleteMemoDialog();
    if (!mounted || !confirmed) {
      return;
    }

    _dismissKeyboard();
    _autosaveTimer?.cancel();

    setState(() {
      _isDeleting = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('memos')
          .doc(_currentMemoId)
          .delete();

      if (!mounted) {
        return;
      }

      _isDiscardingOrDeleted = true;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Note deleted.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) {
        return;
      }

      _showMessage('Failed to delete note. Please try again.');
      setState(() {
        _isDeleting = false;
      });
    }
  }

  Future<bool> _showDeleteMemoDialog() async {
    final title = _titleController.text.trim().isEmpty
        ? _fallbackTitle(_bodyController.text)
        : _titleController.text.trim();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 10,
          backgroundColor: Colors.white,
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _cardBorder),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFAC638).withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 45,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppTheme.lightBackground,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: AppTheme.error,
                      size: 31,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Delete this note?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: _primaryColor,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'This will permanently remove "$title".',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.mutedText,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () => Navigator.of(dialogContext).pop(true),
                  child: Container(
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppTheme.error,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.error.withValues(alpha: 0.18),
                          blurRadius: 15,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'Delete',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.lightBackground),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      backgroundColor: AppTheme.lightBackground,
                      foregroundColor: _primaryColor,
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    return result ?? false;
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _titleFocusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _bodyFocusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _bodyScrollController.dispose();
    _titleController
      ..removeListener(_handleFieldChanged)
      ..dispose();
    _bodyController
      ..removeListener(_handleBodyChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        await _handleBackNavigation();
      },
      child: GestureDetector(
        onTap: _dismissKeyboard,
        behavior: HitTestBehavior.translucent,
        child: Scaffold(
          backgroundColor: _background,
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: statusBarHeight,
                child: const ColoredBox(color: AppTheme.headerBackground),
              ),
              SafeArea(
                child: Center(
                  child: Container(
                    width: 430,
                    constraints: const BoxConstraints(maxWidth: 430),
                    height: double.infinity,
                    color: _background,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Column(
                            children: [
                              const SizedBox(height: 89),
                              Expanded(child: _buildContent(context)),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: _buildAppBar(context),
                        ),
                        Positioned(
                          left: 24,
                          right: 24,
                          bottom: 20,
                          child: _buildBottomActions(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Container(
      height: 89,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: BoxDecoration(
        color: AppTheme.headerBackground,
        boxShadow: const [AppTheme.headerShadow],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          AppTheme.backButton(context, onPressed: _handleBackNavigation),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _buildAppBarTitle(),
            ),
          ),
          _buildDeleteAction(),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportConfig = _detailViewportConfig(
          availableHeight: constraints.maxHeight,
          keyboardInset: keyboardInset,
        );

        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            24,
            0,
            24,
            viewportConfig.scrollBottomPadding,
          ),
          child: Column(
            children: [
              const SizedBox(height: 39),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _cardBorder),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFAC638).withValues(alpha: 0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(25, 21, 25, 25),
                child: LayoutBuilder(
                  builder: (context, cardConstraints) {
                    return _buildEditableBody(
                      context,
                      maxBodyHeight: viewportConfig.maxBodyHeight,
                      contentWidth: cardConstraints.maxWidth,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAppBarTitle() {
    return TextField(
      controller: _titleController,
      focusNode: _titleFocusNode,
      maxLines: 1,
      maxLength: _maxTitleLength,
      inputFormatters: [LengthLimitingTextInputFormatter(_maxTitleLength)],
      textAlign: TextAlign.center,
      textInputAction: TextInputAction.done,
      scrollPhysics: const BouncingScrollPhysics(),
      onSubmitted: (_) => unawaited(_flushAutosave()),
      onTapOutside: (_) => _dismissKeyboard(),
      contextMenuBuilder: _filteredTextFieldContextMenu,
      decoration: InputDecoration(
        hintText: _isCreatingMode ? 'New Note' : 'Note title',
        border: InputBorder.none,
        isCollapsed: true,
        contentPadding: EdgeInsets.zero,
        counterText: '',
      ),
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: _primaryColor,
      ),
    );
  }

  _DetailViewportConfig _detailViewportConfig({
    required double availableHeight,
    required double keyboardInset,
  }) {
    final scrollBottomPadding = math.max(
      _bottomActionsReservedHeight(),
      keyboardInset + 32,
    );
    return _DetailViewportConfig(
      maxBodyHeight: _maxDetailBodyHeight,
      scrollBottomPadding: scrollBottomPadding,
    );
  }

  double _bottomActionsReservedHeight() {
    return _bottomActionButtonHeight +
        _bottomActionBottomOffset +
        _bottomActionTopGap;
  }

  Widget _buildEditableBody(
    BuildContext context, {
    required double maxBodyHeight,
    required double contentWidth,
  }) {
    final bodyHeight = maxBodyHeight.clamp(
      _minDetailBodyHeight,
      _maxDetailBodyHeight,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      height: bodyHeight,
      child: Scrollbar(
        controller: _bodyScrollController,
        thumbVisibility: true,
        radius: const Radius.circular(999),
        child: TextField(
          controller: _bodyController,
          focusNode: _bodyFocusNode,
          scrollController: _bodyScrollController,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          minLines: null,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          onTapOutside: (_) => _dismissKeyboard(),
          contextMenuBuilder: _filteredTextFieldContextMenu,
          scrollPadding: EdgeInsets.only(
            bottom: math.max(32, MediaQuery.viewInsetsOf(context).bottom + 16),
          ),
          decoration: const InputDecoration(
            hintText: 'Write your note here...',
            border: InputBorder.none,
            isCollapsed: true,
          ),
          style: _bodyStyle,
        ),
      ),
    );
  }

  Widget _filteredTextFieldContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final buttonItems = editableTextState.contextMenuButtonItems
        .where((item) {
          final label = item.label?.toLowerCase().trim() ?? '';
          return !label.contains('read aloud') && !label.contains('share');
        })
        .toList(growable: false);

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: _AddToCalendarButton(
        isConverting: _isAnalyzingTask,
        isDisabled: _isSaving || _isDeleting,
        onTap: _analyzeMemoAndOpenTask,
      ),
    );
  }

  Widget _buildDeleteAction() {
    final isDisabled = _isDeleting || _isSaving || _isAnalyzingTask;

    return Opacity(
      opacity: isDisabled ? 0.72 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: isDisabled ? null : _confirmAndDeleteMemo,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppTheme.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppTheme.error.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: AppTheme.error.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: _isAnalyzingTask || _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.error,
                    ),
                  )
                : const Icon(
                    Icons.delete_outline_rounded,
                    color: AppTheme.error,
                    size: 20,
                  ),
          ),
        ),
      ),
    );
  }
}

class _SavedMemo {
  const _SavedMemo({
    required this.memoId,
    required this.title,
    required this.body,
  });

  final String memoId;
  final String title;
  final String body;
}

class _DetailViewportConfig {
  const _DetailViewportConfig({
    required this.maxBodyHeight,
    required this.scrollBottomPadding,
  });

  final double maxBodyHeight;
  final double scrollBottomPadding;
}

class _AddToCalendarButton extends StatelessWidget {
  const _AddToCalendarButton({
    required this.isConverting,
    required this.isDisabled,
    required this.onTap,
  });

  final bool isConverting;
  final bool isDisabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isDisabled ? 0.72 : 1,
      child: GestureDetector(
        onTap: isDisabled || isConverting ? null : onTap,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [AppTheme.accent, AppTheme.accentDark],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accent.withValues(alpha: 0.2),
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: isConverting
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Converting...',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_month_rounded,
                        color: Colors.black87,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Add to Calendar',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _MemoTaskDraft {
  const _MemoTaskDraft({
    required this.title,
    required this.notes,
    required this.category,
    required this.date,
    required this.time,
  });

  final String title;
  final String notes;
  final String? category;
  final DateTime? date;
  final TimeOfDay? time;

  factory _MemoTaskDraft.fromMap(Map<String, dynamic> map) {
    final date = _parseDate(map['dateISO'] as String?);
    final time = _parseTime(map['time24h'] as String?);

    return _MemoTaskDraft(
      title: (map['title'] as String? ?? '').trim(),
      notes: (map['notes'] as String? ?? '').trim(),
      category: (map['category'] as String?)?.trim(),
      date: date,
      time: time,
    );
  }

  static DateTime? _parseDate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value.trim());
  }

  static TimeOfDay? _parseTime(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final parts = value.trim().split(':');
    if (parts.length != 2) {
      return null;
    }

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return null;
    }
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }

    return TimeOfDay(hour: hour, minute: minute);
  }
}
