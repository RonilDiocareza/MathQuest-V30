import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flame/game.dart';
import 'package:just_audio/just_audio.dart';
import '../services/user_progress_service.dart';
import '../game/math_world_game.dart';
import '../game/npc_question.dart';
import '../game/npc_question_dialog.dart';
import '../game/hud.dart';
import '../widgets/game_joystick.dart';

class NumberPickupGameScreen extends StatefulWidget {
  final int level;
  final String problem;
  final int correctAnswer;

  const NumberPickupGameScreen({
    super.key,
    required this.level,
    required this.problem,
    required this.correctAnswer,
  });

  @override
  State<NumberPickupGameScreen> createState() => _NumberPickupGameScreenState();
}

class _NumberPickupGameScreenState extends State<NumberPickupGameScreen> {
  late int currentLevel;
  late String currentProblem;
  late int currentCorrectAnswer;
  late MathWorldGame gameInstance;
  final AudioPlayer _musicPlayer = AudioPlayer();
  final AudioPlayer _soundEffectPlayer = AudioPlayer();
  final AudioPlayer _gameOverSoundPlayer = AudioPlayer();
  Future<void> _soundEffectQueue = Future<void>.value();
  bool levelCompleted = false;
  int score = 0;
  int health = 3;
  bool _isResettingLevel = false;
  bool isMusicEnabled = true;
  bool _isExitDialogOpen = false;
  bool _isGameOverDialogOpen = false;
  bool _isLeaving = false;
  bool _isFinalizingLevel = false;
  bool _completionPending = false;
  bool _correctNumberCollected = false;
  late Future<void> _orientationChange;
  late Future<void> _musicInitialization;

  @override
  void initState() {
    super.initState();
    _orientationChange = _requestGameOrientation();
    _musicInitialization = _initializeMusic();
    currentLevel = widget.level;
    currentProblem = widget.problem;
    currentCorrectAnswer = widget.correctAnswer;
    gameInstance = _createGame();
    gameInstance.pauseWorld();
    _restoreCompletedGameModeScore();
  }

  Future<void> _restoreCompletedGameModeScore() async {
    try {
      final progress = await UserProgressService.getCurrentUserProgress();
      if (!mounted) return;
      if (progress.completedLevels.contains(currentLevel)) {
        final finalScore = progress.gameModeFinalScores[currentLevel] ??
            await UserProgressService.getGameModeFinalScore(currentLevel) ??
            0;
        if (!mounted) return;
        setState(() {
          score = finalScore;
          levelCompleted = true;
        });
        return;
      }
      setState(() {
        score =
            progress.completedNpcQuestionsForLevel(currentLevel).length * 10;
      });
      gameInstance.resumeWorld();
    } catch (error, stackTrace) {
      debugPrint('Unable to restore completed Game Mode score: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) gameInstance.resumeWorld();
    }
  }

  MathWorldGame _createGame() => MathWorldGame(
        level: currentLevel,
        correctAnswer: currentCorrectAnswer,
        problem: currentProblem,
        onNumberCollected: _onCorrectNumberCollected,
        onWrongNumberCollected: _onWrongNumberCollected,
        onNpcQuestion: _onNpcQuestion,
        onNpcQuestionLocked: _showLockedQuestion,
      );

  Future<void> _initializeMusic() async {
    try {
      await _musicPlayer.setAsset(
        'assets/BGM/andorios-arcade_music4-361010.mp3',
      );
      await _musicPlayer.setLoopMode(LoopMode.one);
      if (isMusicEnabled) {
        unawaited(_playMusic());
      }
    } catch (error, stackTrace) {
      if (error is MissingPluginException ||
          error.toString().contains('MissingPluginException')) {
        debugPrint(
            'Audio unavailable in this environment; skipping game music.');
        return;
      }
      debugPrint('Unable to initialize game mode music: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _playMusic() async {
    try {
      await _musicPlayer.play();
    } catch (error, stackTrace) {
      if (error is MissingPluginException ||
          error.toString().contains('MissingPluginException')) {
        return;
      }
      debugPrint('Unable to play game mode music: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _playSoundEffect(String fileName) {
    _soundEffectQueue = _soundEffectQueue.then((_) async {
      try {
        await _soundEffectPlayer.setAsset('assets/BGM/$fileName');
        final duration = _soundEffectPlayer.duration;
        final playbackFinished = duration == null
            ? _soundEffectPlayer.processingStateStream
                .firstWhere((state) => state == ProcessingState.completed)
            : Future<void>.delayed(duration);
        unawaited(
          _soundEffectPlayer.play().catchError(
            (Object error, StackTrace stackTrace) {
              if (error is MissingPluginException ||
                  error.toString().contains('MissingPluginException')) {
                return;
              }
              debugPrint(
                'Unable to start game mode sound effect "$fileName": $error',
              );
              debugPrintStack(stackTrace: stackTrace);
            },
          ),
        );
        await playbackFinished;
      } catch (error, stackTrace) {
        if (error is MissingPluginException ||
            error.toString().contains('MissingPluginException')) {
          return;
        }
        debugPrint('Unable to play game mode sound effect "$fileName": $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    });
    return _soundEffectQueue;
  }

  Future<void> _playGameOverSound() async {
    try {
      await _gameOverSoundPlayer.setAsset('assets/BGM/Game Over.mp3');
      final duration = _gameOverSoundPlayer.duration;
      unawaited(
        _gameOverSoundPlayer.play().catchError(
          (Object error, StackTrace stackTrace) {
            if (error is MissingPluginException ||
                error.toString().contains('MissingPluginException')) {
              return;
            }
            debugPrint('Unable to start the game-over sound: $error');
            debugPrintStack(stackTrace: stackTrace);
          },
        ),
      );
      if (duration != null) {
        await Future<void>.delayed(duration);
      }
    } catch (error, stackTrace) {
      if (error is MissingPluginException ||
          error.toString().contains('MissingPluginException')) {
        return;
      }
      debugPrint('Unable to prepare the game-over sound: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _requestGameOrientation() async {
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      debugPrint('Game orientation set to landscape.');
    } catch (error, stackTrace) {
      debugPrint('Unable to set landscape orientation: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _onNpcQuestion(NpcQuestion question) async {
    if (!mounted || levelCompleted || _completionPending || _isLeaving) return;
    final activeGame = gameInstance;
    bool? isCorrect;
    try {
      isCorrect = await showDialog<bool>(
        context: context,
        builder: (_) => NpcQuestionDialog(question: question),
      );
    } finally {
      activeGame.closeNpcQuestion();
    }

    if (!mounted || isCorrect == null) return;

    if (isCorrect) {
      final bool saved;
      try {
        saved = await activeGame.completeNpcQuestion(question.questionNumber);
      } catch (error, stackTrace) {
        debugPrint('Unable to save NPC question progress: $error');
        debugPrintStack(stackTrace: stackTrace);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save your progress. Please try again.'),
          ),
        );
        return;
      }

      if (!mounted) return;
      if (!saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              activeGame.allNpcQuestionsCompleted
                  ? 'All NPC questions are complete.'
                  : 'Complete Question ${activeGame.currentQuestionNumber} first.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }

      final isFinalQuestion = question.questionNumber == NpcQuestion.all.length;
      unawaited(_playSoundEffect('Correct Answer.mp3'));
      setState(() {
        score += 10;
      });
      if (isFinalQuestion) {
        _completionPending = true;
        final victorySound = _playSoundEffect('Victory.mp3');
        activeGame.pauseWorld();
        final navigator = Navigator.of(context);
        await _showLevelClearedDialog(navigator, victorySound);
        if (!mounted) return;
        await _advanceToNextLevel(navigator);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Question ${question.questionNumber} complete! '
            'Question ${activeGame.currentQuestionNumber} unlocked.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    await _handleDamage(
      'Wrong answer. You lost 1 heart. {health} remaining. Try again.',
    );
  }

  Future<void> _showLevelClearedDialog(
    NavigatorState navigator,
    Future<void> victorySound,
  ) async {
    final dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        title: Text('Level Cleared!'),
        content: Text('You completed all six NPC challenges.'),
      ),
    );

    await Future.wait([
      Future<void>.delayed(const Duration(seconds: 2)),
      victorySound,
    ]);
    if (!mounted) return;
    navigator.pop();
    await dialog;
  }

  void _showLockedQuestion(int currentQuestionNumber) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Question locked. Complete Question $currentQuestionNumber first.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _onCorrectNumberCollected() async {
    if (!mounted || levelCompleted || _completionPending) return;

    final correctSound = _playSoundEffect('Correct Answer.mp3');
    final victorySound = _playSoundEffect('Victory.mp3');
    _completionPending = true;
    if (!_correctNumberCollected) {
      _correctNumberCollected = true;
      setState(() => score += 10);
    }
    gameInstance.pauseWorld();

    // Show correct answer indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 60,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Correct!',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final navigator = Navigator.of(context);

    await Future.wait([
      Future<void>.delayed(const Duration(milliseconds: 1500)),
      correctSound,
      victorySound,
    ]);

    if (!mounted) return;
    navigator.pop(); // Close the correct indicator dialog

    await _advanceToNextLevel(navigator);
  }

  Future<void> _advanceToNextLevel(NavigatorState navigator) async {
    if (_isFinalizingLevel || _isLeaving) return;
    _isFinalizingLevel = true;
    try {
      await UserProgressService.completeGameMode(currentLevel, score);
    } catch (error, stackTrace) {
      _isFinalizingLevel = false;
      debugPrint('Unable to persist completed Game Mode score: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => levelCompleted = false);
        gameInstance.pauseWorld();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Could not save the final score. Please try again.',
            ),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => unawaited(_advanceToNextLevel(navigator)),
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    setState(() {
      levelCompleted = true;
      _completionPending = false;
    });
    _isLeaving = true;
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && navigator.canPop()) {
      navigator.pop(true);
    }
  }

  void _onWrongNumberCollected() {
    unawaited(
      _handleDamage('Wrong! Lives left: {health} ❌', snackDuration: 1),
    );
  }

  Future<void> _handleDamage(
    String message, {
    int snackDuration = 2,
  }) async {
    if (!mounted || levelCompleted || health <= 0 || _isGameOverDialogOpen) {
      return;
    }

    setState(() => health--);
    final damageSound = _playSoundEffect('Health Damage.mp3');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message.replaceAll('{health}', '$health')),
        duration: Duration(seconds: snackDuration),
        backgroundColor: Colors.red,
      ),
    );

    if (health > 0) {
      await damageSound;
      return;
    }
    await _handleGameOver(damageSound);
  }

  Future<void> _handleGameOver(Future<void> damageSound) async {
    if (!mounted || _isGameOverDialogOpen) return;
    _isGameOverDialogOpen = true;
    gameInstance.pauseWorld();
    try {
      await _musicInitialization;
      await _musicPlayer.pause();
    } catch (error, stackTrace) {
      debugPrint('Unable to pause game music after game over: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    unawaited(damageSound);
    unawaited(_playGameOverSound());
    if (!mounted) return;

    final shouldRestart = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Game Over'),
        content: const Text('Do you want to restart this level or quit?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Quit'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restart'),
          ),
        ],
      ),
    );
    _isGameOverDialogOpen = false;
    if (!mounted) return;

    if (shouldRestart == true) {
      await _resetCurrentLevel();
      if (isMusicEnabled) {
        unawaited(_playMusic());
      }
    } else {
      _isLeaving = true;
      setState(() {});
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _resetCurrentLevel() async {
    if (!mounted || _isResettingLevel || levelCompleted) return;

    _isResettingLevel = true;
    gameInstance.pauseWorld();
    try {
      await UserProgressService.resetNpcQuestionsForLevel(currentLevel);
    } catch (error, stackTrace) {
      debugPrint('Unable to clear NPC progress for level restart: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not sync level progress. Restarting this attempt locally.',
            ),
          ),
        );
      }
    }
    if (!mounted) return;

    setState(() {
      health = 3;
      score = 0;
      levelCompleted = false;
      gameInstance = _createGame();
      _isResettingLevel = false;
    });
    _completionPending = false;
    _correctNumberCollected = false;
  }

  void _onMusicPressed() {
    setState(() {
      isMusicEnabled = !isMusicEnabled;
    });
    unawaited(_syncMusicPlayback());
  }

  Future<void> _syncMusicPlayback() async {
    try {
      await _musicInitialization;
      if (isMusicEnabled) {
        unawaited(_playMusic());
      } else {
        try {
          await _musicPlayer.pause();
        } catch (error, stackTrace) {
          if (error is MissingPluginException ||
              error.toString().contains('MissingPluginException')) {
            return;
          }
          debugPrint('Unable to pause game mode music: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
      }
    } catch (error, stackTrace) {
      if (error is MissingPluginException ||
          error.toString().contains('MissingPluginException')) {
        return;
      }
      debugPrint('Unable to update game mode music playback: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _onMenuPressed() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Game Menu'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Level: $currentLevel'),
              Text('Score: $score'),
              Text('Health: $health'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Resume'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showExitDialog();
              },
              child: const Text('Quit'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final double minSide = min(screenSize.width, screenSize.height);
    final double edgePadding = (minSide * 0.04).clamp(12.0, 20.0);
    final double directionButtonSize = (minSide * 0.11).clamp(44.0, 56.0);
    final double directionContainerSize =
        (directionButtonSize * 2.1).clamp(110.0, 140.0);
    return PopScope(
      canPop: _isLeaving,
      onPopInvokedWithResult: (_, __) {
        _showExitDialog();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFD09F5C),
        body: FutureBuilder<void>(
          future: _orientationChange,
          builder: (context, orientationSnapshot) {
            if (orientationSnapshot.connectionState != ConnectionState.done) {
              return _buildLoadingState();
            }

            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: GameWidget(
                    game: gameInstance,
                    loadingBuilder: (_) => _buildLoadingState(),
                    errorBuilder: (context, error) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.white,
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Unable to load Game Mode.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              error.toString(),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _showExitDialog,
                              child:
                                  const Text('Return to the previous screen'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Stack(
                    children: [
                      GameHUD(
                        score: score,
                        health: health,
                        onMusicPressed: _onMusicPressed,
                        onMenuPressed: _onMenuPressed,
                        isMusicEnabled: isMusicEnabled,
                      ),
                      Positioned(
                        left: edgePadding,
                        bottom: edgePadding,
                        child: GameJoystick(
                          size: directionContainerSize,
                          onJoystickChanged: (offset) {
                            if (offset.dx.abs() > offset.dy.abs()) {
                              gameInstance.stopMove();
                              if (offset.dx > 0.3) {
                                gameInstance.startMoveRight();
                              } else if (offset.dx < -0.3) {
                                gameInstance.startMoveLeft();
                              }
                            } else {
                              gameInstance.stopMove();
                              if (offset.dy > 0.3) {
                                gameInstance.startMoveDown();
                              } else if (offset.dy < -0.3) {
                                gameInstance.startMoveUp();
                              }
                            }
                          },
                          onJoystickEnd: gameInstance.stopMove,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const ColoredBox(
      color: Color(0xFF17202A),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Loading Game...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showExitDialog() {
    if (!mounted || _isExitDialogOpen || _isLeaving) return;
    _isExitDialogOpen = true;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit Level?'),
        content: const Text('Are you sure you want to go back?'),
        actions: [
          TextButton(
            onPressed: () {
              _isExitDialogOpen = false;
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => _confirmExit(context),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmExit(BuildContext dialogContext) async {
    if (_isLeaving) return;
    _isLeaving = true;
    _isExitDialogOpen = false;
    final navigator = Navigator.of(context);
    Navigator.pop(dialogContext);
    setState(() {});
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && navigator.canPop()) {
      navigator.pop();
    }
  }

  Future<void> _restoreAppOrientation() async {
    try {
      await _orientationChange;
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      debugPrint('Restored portrait orientation after Game Mode.');
    } catch (error, stackTrace) {
      debugPrint('Unable to restore portrait orientation: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  void dispose() {
    unawaited(_restoreAppOrientation());
    unawaited(() async {
      try {
        await _musicPlayer.dispose();
      } catch (error) {
        if (error is! MissingPluginException &&
            !error.toString().contains('MissingPluginException')) {
          rethrow;
        }
      }
    }());
    unawaited(() async {
      try {
        await _soundEffectPlayer.dispose();
      } catch (error) {
        if (error is! MissingPluginException &&
            !error.toString().contains('MissingPluginException')) {
          rethrow;
        }
      }
    }());
    unawaited(() async {
      try {
        await _gameOverSoundPlayer.dispose();
      } catch (error) {
        if (error is! MissingPluginException &&
            !error.toString().contains('MissingPluginException')) {
          rethrow;
        }
      }
    }());
    gameInstance.removeFromParent();
    super.dispose();
  }
}
