import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../services/user_progress_service.dart';
import '../services/leaderboard_service.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_textfield.dart';
import '../widgets/math_background.dart';
import 'number_pickup_game_screen.dart';

class MathProblemScreen extends StatefulWidget {
  final int level;

  const MathProblemScreen({super.key, required this.level});

  @override
  State<MathProblemScreen> createState() => _MathProblemScreenState();
}

class _MathProblemScreenState extends State<MathProblemScreen> {
  late int currentLevel;
  late String problem;
  late int firstOperand;
  late int secondOperand;
  late String operation;
  late int correctAnswer;

  final TextEditingController answerController = TextEditingController();

  String feedback = '';
  bool isCorrect = false;
  bool isWaitingNextQuestion = false;
  bool _isSubmitting = true;
  bool _isGameModeUnlocked = false;
  bool _isGameModeLaunching = false;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    currentLevel = widget.level;
    generateProblem();
    _loadQuestionState();
  }

  Future<void> _loadQuestionState() async {
    try {
      final progress = await UserProgressService.getCurrentUserProgress();
      if (!mounted) return;
      final savedAnswer = progress.levelQuestionAnswers[currentLevel];
      setState(() {
        _isGameModeUnlocked = savedAnswer != null;
        if (savedAnswer != null) {
          firstOperand = savedAnswer.firstOperand;
          secondOperand = savedAnswer.secondOperand;
          operation = savedAnswer.operation;
          correctAnswer = savedAnswer.correctAnswer;
          problem = '$firstOperand $operation $secondOperand = ?';
          isCorrect = true;
          isWaitingNextQuestion = true;
          feedback = 'Correct!';
        }
        _isSubmitting = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Unable to load Level Question completion: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load this question. Please try again.'),
        ),
      );
    }
  }

  @override
  void dispose() {
    answerController.dispose();
    super.dispose();
  }

  void generateProblem() {
    int maxNum = currentLevel * 5;
    final firstNumber = 1 + (currentLevel - 1) * 2;

    int num1 = firstNumber + _random.nextInt(maxNum);

    int num2 = firstNumber + _random.nextInt(maxNum);

    bool isAddition = currentLevel <= 5 || _random.nextBool();

    if (isAddition) {
      firstOperand = num1;
      secondOperand = num2;
      operation = '+';
      problem = '$num1 + $num2 = ?';
      correctAnswer = num1 + num2;
    } else {
      if (num1 < num2) {
        final temp = num1;
        num1 = num2;
        num2 = temp;
      }
      firstOperand = num1;
      secondOperand = num2;
      operation = '-';
      problem = '$num1 - $num2 = ?';
      correctAnswer = num1 - num2;
    }
  }

  Future<void> checkAnswer() async {
    if (_isSubmitting) {
      debugPrint(
        'MathProblemScreen.checkAnswer: ignored duplicate submission '
        'while a submission is in progress.',
      );
      return;
    }

    debugPrint(
      'MathProblemScreen.checkAnswer: starting answer validation '
      'for level $currentLevel.',
    );
    setState(() {
      _isSubmitting = true;
    });

    final userAnswer = int.tryParse(answerController.text);

    if (userAnswer == null) {
      debugPrint(
        'MathProblemScreen.checkAnswer: answer evaluation failed; '
        'input is not a valid integer.',
      );
      setState(() {
        feedback = 'Enter number!';
        isCorrect = false;
        _isSubmitting = false;
      });
      return;
    }

    if (userAnswer == correctAnswer) {
      debugPrint(
        'MathProblemScreen.checkAnswer: answer evaluated as correct; '
        'starting Level Question progress save.',
      );
      final answer = LevelQuestionAnswer(
        firstOperand: firstOperand,
        secondOperand: secondOperand,
        operation: operation,
        correctAnswer: correctAnswer,
      );
      final LevelQuestionCompletion completion;
      try {
        debugPrint(
          'MathProblemScreen.checkAnswer: awaiting '
          'UserProgressService.completeLevelQuestion for level '
          '$currentLevel.',
        );
        completion = await UserProgressService.completeLevelQuestion(
          currentLevel,
          answer,
        );
        debugPrint(
          'MathProblemScreen.checkAnswer: progress save returned '
          'successfully; alreadyCompleted=${completion.wasAlreadyCompleted}.',
        );
      } catch (error, stackTrace) {
        final firebaseDetails = error is FirebaseException
            ? ', firebaseCode=${error.code}, firebaseMessage=${error.message}'
            : '';
        debugPrint(
          'MathProblemScreen.checkAnswer: Level Question progress save '
          'failed; exceptionType=${error.runtimeType}$firebaseDetails, '
          'message=$error.',
        );
        debugPrintStack(stackTrace: stackTrace);
        if (!mounted) return;
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_answerSaveErrorMessage(error)),
          ),
        );
        return;
      }

      if (mounted) {
        setState(() {
          firstOperand = completion.answer.firstOperand;
          secondOperand = completion.answer.secondOperand;
          operation = completion.answer.operation;
          correctAnswer = completion.answer.correctAnswer;
          problem = '$firstOperand $operation $secondOperand = ?';
          feedback = 'Correct!';
          isCorrect = true;
          isWaitingNextQuestion = true;
          _isGameModeUnlocked = true;
          _isSubmitting = false;
        });
      }
      if (!completion.wasAlreadyCompleted) {
        await _saveLeaderboardPoints(10);
      }
    } else {
      debugPrint(
        'MathProblemScreen.checkAnswer: answer evaluated as incorrect; '
        'preserving retry behavior without saving completion.',
      );
      setState(() {
        feedback = 'Wrong!';
        isCorrect = false;
        _isSubmitting = false;
      });
    }
  }

  String _answerSaveErrorMessage(Object error) {
    if (error is! FirebaseException) {
      return 'Could not save your answer. Please try again.';
    }

    return switch (error.code) {
      'permission-denied' =>
        'You do not have permission to save this answer. Please contact support.',
      'unauthenticated' =>
        'Your session has expired. Please sign in again to save your answer.',
      'unavailable' =>
        'Answer saving is temporarily unavailable. Please try again.',
      _ => 'Could not save your answer (${error.code}). Please try again.',
    };
  }

  Future<void> _saveLeaderboardPoints(int points) async {
    try {
      await LeaderboardService.addPoints(points);
    } catch (error, stackTrace) {
      debugPrint('Unable to save leaderboard points: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save your leaderboard score.'),
        ),
      );
    }
  }

  Future<void> _launchGameMode() async {
    if (_isGameModeLaunching) return;
    _isGameModeLaunching = true;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => NumberPickupGameScreen(
          level: currentLevel,
          problem: problem,
          correctAnswer: correctAnswer,
        ),
      ),
    );
    if (!mounted) return;
    _isGameModeLaunching = false;
  }

  //  BACK BUTTON FUNCTION
  void goBack() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit Level?'),
        content: const Text('Are you sure you want to go back?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // close dialog
              Navigator.pop(context); // go back screen
            },
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MathBackground(
        child: SingleChildScrollView(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const SizedBox(height: 30),
                  Text(
                    'Level $currentLevel',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 30),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Column(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _buildMathOperandRow('', firstOperand),
                            _buildMathOperandRow(operation, secondOperand),
                            Container(
                              width: 132,
                              height: 2,
                              color: const Color(0xFFFF9800),
                            ),
                            SizedBox(
                              width: 132,
                              child: Text(
                                isWaitingNextQuestion ? '$correctAnswer' : '?',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFF9800),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        CustomTextField(
                          hint: 'Answer',
                          controller: answerController,
                        ),
                        const SizedBox(height: 15),
                        CustomButton(
                          text: 'Submit',
                          onPressed: (_isSubmitting || isWaitingNextQuestion)
                              ? null
                              : checkAnswer,
                        ),
                        if (feedback.isNotEmpty) ...[
                          const SizedBox(height: 15),
                          Text(
                            feedback,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isCorrect ? Colors.green : Colors.red,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  const Divider(
                    color: Colors.white,
                    thickness: 2,
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    'Or Play the Game!',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      '🎮 Move around the map and collect the correct number to answer the problem!',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 15),
                  CustomButton(
                    text: 'Play Game Mode',
                    onPressed: _isGameModeUnlocked && !_isGameModeLaunching
                        ? _launchGameMode
                        : null,
                  ),
                  if (!_isGameModeUnlocked) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Complete this Problem Level to unlock Game Mode.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  CustomButton(
                    text: 'Back',
                    onPressed: goBack,
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMathOperandRow(String operator, int operand) {
    return SizedBox(
      width: 132,
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              operator,
              textAlign: TextAlign.left,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF9800),
              ),
            ),
          ),
          Expanded(
            child: Text(
              '$operand',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF9800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
