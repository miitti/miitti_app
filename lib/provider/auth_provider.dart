// ignore_for_file: use_build_context_synchronously

// #region depedencies
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:miitti_app/chatPage.dart';
import 'package:miitti_app/commercialScreens/comact_detailspage.dart';
import 'package:miitti_app/commercialScreens/comchat_page.dart';
import 'package:miitti_app/constants/ad_banner.dart';
import 'package:miitti_app/constants/commercial_activity.dart';
import 'package:miitti_app/constants/commercial_user.dart';
import 'package:miitti_app/constants/constants.dart';
import 'package:miitti_app/constants/miitti_activity.dart';
import 'package:miitti_app/constants/person_activity.dart';
import 'package:miitti_app/constants/miittiUser.dart';
import 'package:miitti_app/constants/report.dart';
import 'package:miitti_app/createMiittiActivity/activityDetailsPage.dart';
import 'package:miitti_app/createMiittiActivity/activityPageFinal.dart';
import 'package:miitti_app/helpers/filter_settings.dart';
import 'package:miitti_app/index_page.dart';
import 'package:miitti_app/onboardingScreens/obs3_sms.dart';
import 'package:miitti_app/onboardingScreens/onboarding.dart';
import 'package:miitti_app/utils/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
// #endregion

class AuthProvider extends ChangeNotifier {
// #region Variables

  bool _isSignedIn = false;
  bool get isSignedIn => _isSignedIn;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final FirebaseFirestore _fireStore = FirebaseFirestore.instance;

  String? _uid;
  String get uid => _uid!;
  bool get userNull => _uid == null;

  MiittiUser? _miittiUser;
  MiittiUser get miittiUser => _miittiUser!;

  PersonActivity? _miittiActivity;
  PersonActivity get miittiActivity => _miittiActivity!;

  AuthProvider() {
    checkSign();
  }

// #endregion

// #region SignIn
  Future<bool> checkSign() async {
    final SharedPreferences s = await SharedPreferences.getInstance();
    _isSignedIn = s.getBool('is_signedin') ?? false;
    notifyListeners();
    return _isSignedIn;
  }

  Future setSignIn() async {
    SharedPreferences s = await SharedPreferences.getInstance();
    await s.setBool('is_signedin', true);
    _isSignedIn = true;
    notifyListeners();
  }

  void signInWithPhone(BuildContext context, String phoneNumber) async {
    try {
      _isLoading = true;
      notifyListeners();
      await _firebaseAuth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential phoneAuthCredential) async {
          User? user =
              (await _firebaseAuth.signInWithCredential(phoneAuthCredential))
                  .user;
          _uid = user?.uid;

          showSnackBar(
              context, "Koodi saatu automaattisesti!", Colors.green.shade600);

          checkExistingUser().then((value) async {
            if (value == true) {
              getDataFromFirestore().then(
                (value) => saveUserDataToSP().then(
                  (value) => setSignIn().then(
                    (value) => Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                            builder: (context) => const IndexPage()),
                        (Route<dynamic> route) => false),
                  ),
                ),
              );
            } else {
              Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                      builder: (context) => const OnboardingScreen()),
                  (Route<dynamic> route) => false);
            }
          });
          _isLoading = false;
          notifyListeners();
          debugPrint("$phoneNumber signed in");
        },
        verificationFailed: (error) {
          _isLoading = false;
          notifyListeners();
          showSnackBar(context, "Failed phone verification: $error",
              Colors.red.shade800);

          throw Exception(error.message);
        },
        codeSent: (verificationId, forceResendingToken) {
          _isLoading = false;
          notifyListeners();
          debugPrint("sending code to $phoneNumber");
          if (context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => OnBordingScreenSms(
                  verificationId: verificationId,
                ),
              ),
            );
          }
        },
        codeAutoRetrievalTimeout: (verificationId) {},
      );
    } on FirebaseAuthException catch (e) {
      _isLoading = false;
      notifyListeners();
      debugPrint("Kirjautuminen epäonnistui: ${e.message}");
      showSnackBar(context, "Kirjautuminen epäonnistui: ${e.message}",
          Colors.red.shade800);
    }
  }

  void verifyOtp({
    required BuildContext context,
    required String verificationId,
    required String userOtp,
    required Function onSuccess,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      PhoneAuthCredential creds = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: userOtp,
      );

      User? user = (await _firebaseAuth.signInWithCredential(creds)).user;
      _uid = user?.uid;

      onSuccess();
    } on FirebaseAuthException catch (e) {
      print("Vahvistus epäonnistui: ${e.message} (${e.code})");
      showSnackBar(context, 'SMS vahvistus epäonnistui ${e.message}',
          Colors.red.shade800);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

// #endregion

// #region Report

  Future<void> reportUser(
      String message, String reportedId, String senderId) async {
    try {
      _isLoading = true;
      notifyListeners();

      DocumentSnapshot documentSnapshot =
          await _fireStore.collection('reportedUsers').doc(reportedId).get();

      Report report;
      if (documentSnapshot.exists) {
        report = Report.fromMap(
            documentSnapshot.data() as Map<String, dynamic>, true);
        report.reasons.add("$senderId: $message");
      } else {
        report = Report(
          reportedId: reportedId,
          reasons: ["$senderId: $message"],
          isUser: true,
        );
      }
      await _fireStore
          .collection('reportedUsers')
          .doc(reportedId)
          .set(report.toMap());
    } catch (e) {
      print("Reporting failed: $e");
    } finally {
      Timer(const Duration(seconds: 1), () {
        _isLoading = false;
        notifyListeners();
      });
    }
  }

  Future<void> reportActivity(
      String message, String reportedId, String senderId) async {
    try {
      _isLoading = true;
      notifyListeners();

      DocumentSnapshot documentSnapshot = await _fireStore
          .collection('reportedActivities')
          .doc(reportedId)
          .get();

      Report report;
      if (documentSnapshot.exists) {
        report = Report.fromMap(
            documentSnapshot.data() as Map<String, dynamic>, false);
        report.reasons.add("$senderId: $message");
      } else {
        report = Report(
          reportedId: reportedId,
          reasons: ["$senderId: $message"],
          isUser: false,
        );
      }
      await _fireStore
          .collection('reportedActivities')
          .doc(reportedId)
          .set(report.toMap());
    } catch (e) {
      print("Reporting failed: $e");
    } finally {
      Timer(const Duration(seconds: 1), () {
        _isLoading = false;
        notifyListeners();
      });
    }
  }

  Future<List<PersonActivity>> fetchReportedActivities() async {
    try {
      QuerySnapshot querySnapshot =
          await _fireStore.collection('reportedActivities').get();

      List<PersonActivity> list = [];

      for (QueryDocumentSnapshot report in querySnapshot.docs) {
        DocumentSnapshot<Map<String, dynamic>> doc =
            await _fireStore.collection("activities").doc(report.id).get();
        list.add(PersonActivity.fromMap(doc.data() as Map<String, dynamic>));
      }

      return list;
    } catch (e) {
      print('Error fetching reported activities: $e');
      return [];
    }
  }

// #endregion

// #region Ads
  Future<List<AdBanner>> fetchAds() async {
    try {
      QuerySnapshot querySnapshot =
          await _fireStore.collection('adBanners').get();

      List<AdBanner> list = querySnapshot.docs
          .map((doc) => AdBanner.fromMap(doc.data() as Map<String, dynamic>))
          .toList();

      return AdBanner.sortBanners(list, miittiUser);
    } catch (e) {
      print("Error fetching ads $e");
      return [];
    }
  }

  Future addAdView(String adUid) async {
    try {
      _isLoading = true;
      notifyListeners();

      await _fireStore.collection('adBanners').doc(adUid).update({
        'views': FieldValue.increment(1),
      });
    } catch (e) {
      print('Error adding view: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future addAdClick(String adUid) async {
    try {
      _isLoading = true;
      notifyListeners();

      await _fireStore.collection('adBanners').doc(adUid).update({
        'clicks': FieldValue.increment(1),
      });
    } catch (e) {
      print('Error adding view: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
// #endregion

// #region Activities

  void saveMiittiActivityDataToFirebase({
    required BuildContext context,
    required PersonActivity activityModel,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      activityModel.admin = _miittiUser!.uid;
      activityModel.adminAge = calculateAge(_miittiUser!.userBirthday);
      activityModel.adminGender = _miittiUser!.userGender;
      activityModel.activityUid = generateCustomId();
      activityModel.participants.add(_miittiUser!.uid);

      _miittiActivity = activityModel;

      await _fireStore
          .collection('activities')
          .doc(activityModel.activityUid)
          .set(activityModel.toMap())
          .then((value) {
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => ActivityPageFinal(
                miittiActivity: _miittiActivity!,
              ),
            ),
            (Route<dynamic> route) => false);

        _isLoading = false;
        notifyListeners();
      }).onError(
        (error, stackTrace) {},
      );
    } on FirebaseAuthException catch (e) {
      showSnackBar(context, e.message.toString(), Colors.red.shade800);
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<MiittiActivity>> fetchActivities() async {
    try {
      FilterSettings filterSettings = FilterSettings();
      await filterSettings.loadPreferences();

      QuerySnapshot querySnapshot =
          await _fireStore.collection('activities').get();

      List<MiittiActivity> activities = querySnapshot.docs
          .map((doc) =>
              PersonActivity.fromMap(doc.data() as Map<String, dynamic>))
          .where((activity) {
        if (_miittiUser == null) {
          print("User is null");
        } else {
          print("Checking filters of ${_miittiUser?.userName}");
          if (daysSince(activity.activityTime) <
              (activity.timeDecidedLater ? -14 : -1)) {
            removeActivity(activity.activityUid);
            return false;
          }

          if (filterSettings.sameGender &&
              activity.adminGender != miittiUser.userGender) {
            return false;
          }
          if (!filterSettings.multiplePeople && activity.personLimit > 2) {
            return false;
          }
          if (activity.adminAge < filterSettings.minAge ||
              activity.adminAge > filterSettings.maxAge) {
            return false;
          }
        }

        return true;
      }).toList();

      QuerySnapshot commercialQuery =
          await _fireStore.collection('commercialActivities').get();

      List<MiittiActivity> comActivities = commercialQuery.docs
          .map((doc) =>
              CommercialActivity.fromMap(doc.data() as Map<String, dynamic>))
          .where((activity) {
        if (_miittiUser == null) {
          print("User is null");
        } else {
          print("Checking filters of ${_miittiUser?.userName}");
          if (daysSince(activity.endTime) < -1) {
            return false;
          }
        }

        return true;
      }).toList();

      List<MiittiActivity> list = List<MiittiActivity>.from(activities);
      list.addAll(List<MiittiActivity>.from(comActivities));
      return list;
    } catch (e, s) {
      print('Error fetching activities: $e');
      print(s);
      return [];
    }
  }

  Future<List<MiittiActivity>> fetchUserActivities() async {
    try {
      QuerySnapshot querySnapshot = await _fireStore
          .collection('activities')
          .where('participants', arrayContains: uid)
          .get();

      QuerySnapshot commercialSnapshot = await _fireStore
          .collection('commercialActivities')
          .where('participants', arrayContains: uid)
          .get();

      QuerySnapshot requestSnapshot = await _fireStore
          .collection('activities')
          .where('requests', arrayContains: uid)
          .get();

      List<PersonActivity> personActivities = [];
      List<CommercialActivity> commercialActivities = [];

      for (var doc in querySnapshot.docs) {
        personActivities
            .add(PersonActivity.fromMap(doc.data() as Map<String, dynamic>));
      }

      for (var doc in commercialSnapshot.docs) {
        commercialActivities.add(
            CommercialActivity.fromMap(doc.data() as Map<String, dynamic>));
      }

      for (var doc in requestSnapshot.docs) {
        personActivities
            .add(PersonActivity.fromMap(doc.data() as Map<String, dynamic>));
      }

      DocumentSnapshot documentSnapshot =
          await _fireStore.collection('users').doc(_uid).get();

      MiittiUser myOwnUser =
          MiittiUser.fromMap(documentSnapshot.data() as Map<String, dynamic>);

      if (myOwnUser.invitedActivities.isNotEmpty) {
        for (String activityId in myOwnUser.invitedActivities) {
          DocumentSnapshot activitySnapshot =
              await _fireStore.collection('activities').doc(activityId).get();

          if (activitySnapshot.exists) {
            PersonActivity activity = PersonActivity.fromMap(
                activitySnapshot.data() as Map<String, dynamic>);
            personActivities.add(activity);
          }
        }
      }

      List<MiittiActivity> list = List<MiittiActivity>.from(personActivities);
      list.addAll(List<MiittiActivity>.from(commercialActivities));
      return list;
    } catch (e) {
      print('Error fetching user activities: $e');
      return [];
    }
  }

  Future removeActivity(String activityId) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _fireStore
          .collection('activities')
          .doc(activityId)
          .delete()
          .then((value) => print("Activity Removed!"));

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      print('Error deleteing  activity: $e');
      return [];
    }
  }

  Future<List<PersonActivity>> fetchAdminActivities() async {
    _isLoading = true;
    notifyListeners();
    try {
      QuerySnapshot querySnapshot = await _fireStore
          .collection('activities')
          .where('admin', isEqualTo: uid)
          .get();

      List<PersonActivity> activities = querySnapshot.docs
          .map((doc) =>
              PersonActivity.fromMap(doc.data() as Map<String, dynamic>))
          .toList();

      _isLoading = false;
      notifyListeners();

      return activities;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      print('Error fetching user activities: $e');
      return [];
    }
  }

  Future<int> adminActivitiesLength() async {
    _isLoading = true;
    notifyListeners();
    try {
      QuerySnapshot querySnapshot = await _fireStore
          .collection('activities')
          .where('admin', isEqualTo: uid)
          .get();

      _isLoading = false;
      notifyListeners();

      return querySnapshot.docs.length;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      print('Error fetching user activities: $e');
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> fetchActivitiesRequests() async {
    _isLoading = true;
    notifyListeners();

    try {
      QuerySnapshot querySnapshot = await _fireStore
          .collection('activities')
          .where('admin', isEqualTo: uid)
          .get();

      List<PersonActivity> activities = querySnapshot.docs
          .map((doc) =>
              PersonActivity.fromMap(doc.data() as Map<String, dynamic>))
          .toList();

      List<Map<String, dynamic>> usersAndActivityIds = [];

      for (PersonActivity activity in activities) {
        List<MiittiUser> users = await fetchUsersByUids(activity.requests);
        usersAndActivityIds.addAll(users.map((user) => {
              'user': user,
              'activity': activity,
            }));
      }

      _isLoading = false;
      notifyListeners();

      return usersAndActivityIds.toList();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      print('Error fetching admin activities: $e');
      return [];
    }
  }

  Future<List<PersonActivity>> fetchActivitiesRequestsFrom(
      String userId) async {
    _isLoading = true;
    notifyListeners();

    try {
      QuerySnapshot querySnapshot = await _fireStore
          .collection('activities')
          .where('admin', isEqualTo: uid)
          .where('requests', arrayContains: userId)
          .get();

      List<PersonActivity> activities = querySnapshot.docs
          .map((doc) =>
              PersonActivity.fromMap(doc.data() as Map<String, dynamic>))
          .toList();

      _isLoading = false;
      notifyListeners();

      return activities.toList();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      print('Error fetching admin activities: $e');
      return [];
    }
  }

  Future<PersonActivity> getSingleActivity(String activityId) async {
    _isLoading = true;
    notifyListeners();
    DocumentSnapshot doc =
        await _fireStore.collection("activities").doc(activityId).get();
    PersonActivity activity =
        PersonActivity.fromMap(doc.data() as Map<String, dynamic>);
    _isLoading = false;
    notifyListeners();
    return activity;
  }

  Future<Widget> getDetailsPage(String activityId) async {
    _isLoading = true;
    notifyListeners();
    Widget widget;
    DocumentSnapshot personDoc =
        await _fireStore.collection("activities").doc(activityId).get();
    if (personDoc.exists) {
      widget = ActivityDetailsPage(
          myActivity:
              PersonActivity.fromMap(personDoc.data() as Map<String, dynamic>));
    } else {
      DocumentSnapshot commercialDoc = await _fireStore
          .collection("commercialActivities")
          .doc(activityId)
          .get();
      widget = ComActDetailsPage(
          myActivity: CommercialActivity.fromMap(
              commercialDoc.data() as Map<String, dynamic>));
    }
    _isLoading = false;
    notifyListeners();
    return widget;
  }

// #endregion

// #region UsersInActivities

  Future<void> sendActivityRequest(String activityId) async {
    try {
      _isLoading = true;
      notifyListeners();

      await _fireStore.collection('activities').doc(activityId).update({
        'requests': FieldValue.arrayUnion([_uid])
      }).then((value) {
        print("User joined the activity successfully");
      }).catchError((error) {
        print("Error joining the activity: $error");
      });
    } catch (e) {
      print('Error while joining activity: $e');
    } finally {
      Timer(const Duration(seconds: 1), () {
        _isLoading = false;
        notifyListeners();
      });
    }
  }

  Future<void> joinActivity(String activityId) async {
    try {
      _isLoading = true;
      notifyListeners();

      await _fireStore
          .collection('commercialActivities')
          .doc(activityId)
          .update({
        'participants': FieldValue.arrayUnion([_uid])
      }).then((value) {
        print("User joined the activity successfully");
      }).catchError((error) {
        print("Error joining the activity: $error");
      });
    } catch (e) {
      print('Error while joining activity: $e');
    } finally {
      Timer(const Duration(seconds: 1), () {
        _isLoading = false;
        notifyListeners();
      });
    }
  }

  Future<bool> reactToInvite(String activityId, bool accepted) async {
    _isLoading = true;
    notifyListeners();
    bool operationCompleted = false;
    try {
      DocumentReference userRef = _fireStore.collection('users').doc(uid);
      DocumentSnapshot userSnapshot = await userRef.get();

      if (userSnapshot.exists) {
        MiittiUser user =
            MiittiUser.fromMap(userSnapshot.data() as Map<String, dynamic>);
        user.invitedActivities.remove(activityId);

        await userRef
            .update({'invitedActivities': user.invitedActivities.toList()});

        if (accepted) {
          await updateUserJoiningActivity(activityId, uid, true);
          operationCompleted = true;
        }
      }
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      print('Found error accepting invite: $e');
    }
    return operationCompleted;
  }

  Future inviteUserToYourActivity(
    String userId,
    String activityId,
  ) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Get the document reference for the user who is getting invited
      DocumentReference invitedRef = _fireStore.collection('users').doc(userId);

      // Get the document snapshot of the invited user
      DocumentSnapshot invitedPersonSnapshot =
          await _fireStore.collection('users').doc(userId).get();

      if (invitedPersonSnapshot.exists) {
        // Convert the document snapshot to MiittiUser object

        MiittiUser invitedUser = MiittiUser.fromMap(
            invitedPersonSnapshot.data() as Map<String, dynamic>);

        // Add the activityId to the invitedActivities set of the invitedUser
        invitedUser.invitedActivities.add(activityId);

        // Update the 'invitedActivities' field in Firestore
        await invitedRef.update(
            {'invitedActivities': invitedUser.invitedActivities.toList()});
      }

      _isLoading = false;
      notifyListeners();
      return;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      debugPrint('Got this error while inviting user to your activity $e');
    }
  }

  Future<bool> checkIfUserJoined(String activityUid,
      {bool commercial = false}) async {
    final snapshot = await FirebaseFirestore.instance
        .collection(commercial ? 'commercialActivities' : 'activities')
        .doc(activityUid)
        .get();

    if (snapshot.exists) {
      final activity = commercial
          ? CommercialActivity.fromMap(snapshot.data() as Map<String, dynamic>)
          : PersonActivity.fromMap(snapshot.data() as Map<String, dynamic>);
      return activity.participants.contains(uid);
    }

    return false;
  }

  Future<bool> checkIfUserRequested(String activityUid) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('activities')
        .doc(activityUid)
        .get();

    if (snapshot.exists) {
      final activity =
          PersonActivity.fromMap(snapshot.data() as Map<String, dynamic>);
      return activity.requests.contains(uid);
    }

    return false;
  }

  Future<bool> updateUserJoiningActivity(
    String activityId,
    String userId,
    bool accept,
  ) async {
    _isLoading = true;
    notifyListeners();
    bool joined = false;

    try {
      final activityRef = _fireStore.collection('activities').doc(activityId);

      await _fireStore.runTransaction((transaction) async {
        final activitySnapshot = await transaction.get(activityRef);
        if (!activitySnapshot.exists) {
          print('Activity does not exist.');
          return;
        }

        final activityData = activitySnapshot.data();
        final List<dynamic> participants = activityData?['participants'];
        final List<dynamic> requests = activityData?['requests'];

        // Remove user ID from requests
        requests.remove(userId);

        // Add user ID to participants if not already present
        if (!participants.contains(userId) && accept) {
          participants.add(userId);
          joined = true;
        }

        transaction.update(activityRef, {
          'participants': participants,
          'requests': requests,
        });
      });

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      print('Error while joining activity: $e');
    }
    return joined;
  }

  Future<void> removeUserFromActivity(
    String activityId,
    bool isRequested,
  ) async {
    _isLoading = true;
    notifyListeners();
    try {
      if (!isRequested) {
        await _fireStore.collection('activities').doc(activityId).update({
          'participants': FieldValue.arrayRemove([uid])
        });
      } else {
        await _fireStore.collection('activities').doc(activityId).update({
          'requests': FieldValue.arrayRemove([uid])
        });
      }

      print("User removed from activity successfully.");

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      print('Error removing user from activity: $e');
    }
  }

  Future getGroupAdmin(String activityId) async {
    DocumentReference d = _fireStore.collection('activities').doc(activityId);
    DocumentSnapshot documentSnapshot = await d.get();
    return documentSnapshot['admin'];
  }

// #endregion

// #region Chatting

  Future<Widget> getChatPage(String activityId) async {
    _isLoading = true;
    notifyListeners();
    Widget widget;
    DocumentSnapshot personDoc =
        await _fireStore.collection("activities").doc(activityId).get();
    if (personDoc.exists) {
      widget = ChatPage(
          activity:
              PersonActivity.fromMap(personDoc.data() as Map<String, dynamic>));
    } else {
      DocumentSnapshot commercialDoc = await _fireStore
          .collection("commercialActivities")
          .doc(activityId)
          .get();
      widget = ComChatPage(
          activity: CommercialActivity.fromMap(
              commercialDoc.data() as Map<String, dynamic>));
    }
    _isLoading = false;
    notifyListeners();
    return widget;
  }

  getChats(String activityId) async {
    return _fireStore
        .collection('activities')
        .doc(activityId)
        .collection('messages')
        .orderBy('time', descending: true)
        .snapshots();
  }

  sendMessage(String activityId, Map<String, dynamic> chatMessageData) async {
    await _fireStore
        .collection('activities')
        .doc(activityId)
        .collection("messages")
        .add(chatMessageData);

    await _fireStore.collection('activities').doc(activityId).update({
      "recentMessage": chatMessageData['message'],
      "recentMessageSender": chatMessageData['sender'],
      "recentMessageTime": chatMessageData['time'].toString(),
    });
  }

// #endregion

// #region ThisUser

  Future<bool> checkExistingUser() async {
    DocumentSnapshot snapshot =
        await _fireStore.collection('users').doc(_uid).get();
    if (snapshot.exists) {
      return true;
    }
    return false;
  }

  void saveUserDatatoFirebase({
    required BuildContext context,
    required MiittiUser userModel,
    required File? image,
    required Function onSucess,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      await uploadUserImage(_firebaseAuth.currentUser!.uid, image)
          .then((value) {
        userModel.profilePicture = value;
      }).onError((error, stackTrace) {});
      userModel.userPhoneNumber = _firebaseAuth.currentUser!.phoneNumber!;
      userModel.uid = _firebaseAuth.currentUser!.uid;
      _miittiUser = userModel;

      await _fireStore
          .collection('users')
          .doc(_uid)
          .set(userModel.toMap())
          .then((value) {
        onSucess();
        _isLoading = false;
        notifyListeners();
      }).onError(
        (error, stackTrace) {},
      );
    } on FirebaseAuthException catch (e) {
      showSnackBar(context, e.message.toString(), Colors.red.shade800);
      print("Userdata to firebase error: $e");
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String> uploadUserImage(String uid, File? image) async {
    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      // contentType: 'image/png',
      customMetadata: {'picked-file-path': image!.path},
    );

    String filePath = 'userImages/$uid/profilePicture.jpg';
    try {
      final UploadTask uploadTask;
      Reference ref = FirebaseStorage.instance.ref(filePath);

      uploadTask = ref.putData(await image.readAsBytes(), metadata);

      String imageUrl = await (await uploadTask).ref.getDownloadURL();

      return imageUrl;
    } catch (error) {
      throw Exception("Upload failed: $error");
    }
  }

  Future saveUserDataToSP() async {
    SharedPreferences s = await SharedPreferences.getInstance();
    await s.setString('user_model', json.encode(miittiUser.toMap()));
  }

  Future getDataFromSp() async {
    SharedPreferences s = await SharedPreferences.getInstance();
    String data = s.getString('user_model') ?? '';
    _miittiUser = MiittiUser.fromMap(jsonDecode(data));
    _uid = _miittiUser!.uid;
    notifyListeners();
  }

  Future getDataFromFirestore() async {
    await _fireStore
        .collection('users')
        .doc(_firebaseAuth.currentUser!.uid)
        .get()
        .then((DocumentSnapshot snapshot) {
      _miittiUser = MiittiUser(
          userName: snapshot['userName'],
          userEmail: snapshot['userEmail'],
          uid: snapshot['uid'],
          userPhoneNumber: snapshot['userPhoneNumber'],
          userBirthday: snapshot['userBirthday'],
          userArea: snapshot['userArea'],
          userFavoriteActivities:
              (snapshot['userFavoriteActivities'] as List<dynamic>)
                  .cast<String>()
                  .toSet(),
          userChoices: (snapshot['userChoices'] as Map<String, dynamic>)
              .cast<String, String>(),
          userGender: snapshot['userGender'],
          userLanguages: (snapshot['userLanguages'] as List<dynamic>)
              .cast<String>()
              .toSet(),
          profilePicture: snapshot['profilePicture'],
          invitedActivities: (snapshot['invitedActivities'] as List<dynamic>)
              .cast<String>()
              .toSet(),
          userStatus: snapshot['userStatus'],
          userSchool: snapshot['userSchool'],
          fcmToken: snapshot['fcmToken'],
          userRegistrationDate: snapshot['userRegistrationDate']);
      _uid = _miittiUser!.uid;
    }).onError((error, stackTrace) {
      print('ERROR: ${error.toString()}');
    });
  }

  Future<void> setUserStatus() async {
    try {
      DateTime now = DateTime.now().toUtc();
      String timestampString = now.toIso8601String();
      await _fireStore
          .collection('users')
          .doc(_uid)
          .update({'userStatus': timestampString});
      print("Userstatus set");
    } catch (e, s) {
      if (_uid == null) print("UID is null");
      print('Got an error setting user status $e and my uid is $_uid');
      print('$s');
    }
  }

  Future userSignOut() async {
    SharedPreferences s = await SharedPreferences.getInstance();
    await _firebaseAuth.signOut();
    _isSignedIn = false;
    notifyListeners();
    s.clear();
  }

  Future<void> updateUserInfo(MiittiUser updatedUser, File? imageFile) async {
    _isLoading = true;
    notifyListeners();
    try {
      if (imageFile != null) {
        await uploadUserImage(_firebaseAuth.currentUser!.uid, imageFile)
            .then((value) {
          updatedUser.profilePicture = value;
        }).onError((error, stackTrace) {
          print("HATA UPDATEUSERINFO: $error");
        });
      }

      await _fireStore
          .collection('users')
          .doc(_uid)
          .update(updatedUser.toMap())
          .then((value) {
        _miittiUser = updatedUser;
        _isLoading = false;
        notifyListeners();
      });

      // Update the user in the provider

      notifyListeners();
    } on FirebaseAuthException catch (e) {
      print('Error updating user info: ${e.message}');
    }
  }

  Future<int> removeUser(String userId) async {
    _isLoading = true;
    notifyListeners();
    try {
      int value = 0;

      await _fireStore.collection('users').doc(userId).delete().then((v) {
        value = 1;
      });

      if (!adminId.contains(_firebaseAuth.currentUser!.uid) &&
          _firebaseAuth.currentUser!.uid.isNotEmpty) {
        value = 0;
        await _firebaseAuth.currentUser?.delete().then((v) {
          value = 1;
        });
      }

      if (value == 1 && !adminId.contains(userId)) {
        SharedPreferences s = await SharedPreferences.getInstance();
        _isSignedIn = false;
        await s.clear().then((v) {
          if (v) {
            value = 2;
          }
        });
      }

      _isLoading = false;
      notifyListeners();
      return value;
    } catch (e, s) {
      _isLoading = false;
      notifyListeners();
      print("Error removing user from the app $e");
      await FirebaseCrashlytics.instance
          .recordError(e, s, reason: 'a non-fatal error');
      return 0;
    }
  }

// #endregion

// #region Users

  Future<List<MiittiUser>> fetchUsers() async {
    QuerySnapshot querySnapshot = await _fireStore.collection('users').get();

    return querySnapshot.docs
        .map((doc) => MiittiUser.fromMap(doc.data() as Map<String, dynamic>))
        .toList();
  }

  List<MiittiUser> filterUsersBasedOnArea(
      MiittiUser currentUser, List<MiittiUser> allUsers) {
    return allUsers.where((user) {
      if (user.uid == currentUser.uid) return false; // Exclude the current user

      bool sameCity = user.userArea == currentUser.userArea;

      return sameCity;
    }).toList();
  }

  List<MiittiUser> filterUsersBasedOnInterests(
      MiittiUser currentUser, List<MiittiUser> allUsers) {
    return allUsers.where((user) {
      if (user.uid == currentUser.uid) return false; // Exclude the current user

      Set<String> commonInterests = user.userFavoriteActivities
          .toSet()
          .intersection(currentUser.userFavoriteActivities.toSet());

      // If there are common interests, include the user in the list
      return commonInterests.isNotEmpty;
    }).toList();
  }

  Future<MiittiUser> getUser(String id) async {
    _isLoading = true;
    notifyListeners();
    DocumentSnapshot doc = await _fireStore.collection("users").doc(id).get();
    MiittiUser user = MiittiUser.fromMap(doc.data() as Map<String, dynamic>);
    _isLoading = false;
    notifyListeners();
    return user;
  }

  Future<CommercialUser> getCommercialUser(String id) async {
    _isLoading = true;
    notifyListeners();
    DocumentSnapshot doc =
        await _fireStore.collection("commercialUsers").doc(id).get();
    CommercialUser user =
        CommercialUser.fromMap(doc.data() as Map<String, dynamic>);
    _isLoading = false;
    notifyListeners();
    return user;
  }

  Future<List<MiittiUser>> fetchUsersByActivityId(String activityId) async {
    try {
      // Fetch activity by id
      DocumentSnapshot personSnapshot =
          await _fireStore.collection('activities').doc(activityId).get();
      if (personSnapshot.exists) {
        PersonActivity activity = PersonActivity.fromMap(
            personSnapshot.data() as Map<String, dynamic>);

        // Fetch participants (users) using user ids from the activity
        return await fetchUsersByUids(activity.participants);
      } else {
        DocumentSnapshot commercialSnapshot = await _fireStore
            .collection('commercialActivities')
            .doc(activityId)
            .get();

        CommercialActivity commercialActivity = CommercialActivity.fromMap(
            commercialSnapshot.data() as Map<String, dynamic>);
        print(
            "Fetching participants of commecialActivity ${commercialActivity.activityTitle}. It has ${commercialActivity.participants.length} participants");
        return await fetchUsersByUids(commercialActivity.participants);
      }
    } catch (e) {
      print("Error fetching users by activity id: $e");
      return [];
    }
  }

  Future<List<MiittiUser>> fetchUsersByUids(Set<String> userIds) async {
    try {
      List<MiittiUser> users = [];
      for (final uid in userIds) {
        DocumentSnapshot docSnapshot =
            await _fireStore.collection('users').doc(uid).get();
        if (docSnapshot.exists) {
          users.add(
              MiittiUser.fromMap(docSnapshot.data() as Map<String, dynamic>));
        } else {
          print("User not found");
        }
      }
      return users;
    } catch (e) {
      print("Error fetching users: $e");
      return [];
    }
  }
// #endregion
}
