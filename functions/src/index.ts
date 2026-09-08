/**
 * Firebase Cloud Functions Backend (TypeScript)
 * Serverless API endpoints for IP-based Listening History & Collaborative Recommendations.
 * 
 * Exposes:
 * 1. logPlayback - HTTPS POST to log track completion, auto-detecting client IP.
 * 2. getTrending - HTTPS GET to retrieve top global trending tracks (excluding client IP).
 * 3. getCollabNextTrack - HTTPS GET to fetch collaborative next-track based on current track and client IP.
 */

import { onRequest } from 'firebase-functions/v2/https';
import { onDocumentUpdated, onDocumentCreated } from 'firebase-functions/v2/firestore';
import * as logger from 'firebase-functions/logger';
import * as admin from 'firebase-admin';
import { getFirestore } from 'firebase-admin/firestore';

// Initialize Firebase Admin SDK
if (admin.apps.length === 0) {
  admin.initializeApp();
}
const db = admin.firestore();
const chatDb = getFirestore('chat');

// Helper to extract clean Client IP from request headers (supports proxies/CDNs)
function getClientIp(req: any): string {
  const forwarded = req.headers['x-forwarded-for'];
  if (forwarded) {
    // x-forwarded-for can be a comma-separated list of IPs. Grab the first one.
    return (typeof forwarded === 'string' ? forwarded : forwarded[0]).split(',')[0].trim();
  }
  return req.ip || req.socket?.remoteAddress || 'unknown_ip';
}

// ─────────────────────────────────────────────────────────────────────────────
// FUNCTION 1: Log Playback (IP-Based User Identity)
// ─────────────────────────────────────────────────────────────────────────────
export const logPlayback = onRequest({ cors: true }, async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).json({ success: false, message: 'Method Not Allowed' });
    return;
  }

  try {
    const { trackObject, context } = req.body;
    
    if (!trackObject?.id || !trackObject?.title) {
      res.status(400).json({ success: false, message: 'Missing trackObject metadata' });
      return;
    }

    // Auto-detect user identity using client IP
    const userIp = getClientIp(req);

    const historyRef = db.collection('listening_history');
    await historyRef.add({
      userId: userIp, // Store IP as user identity
      trackId: trackObject.id,
      trackTitle: trackObject.title,
      artistName: trackObject.artist || 'Unknown Artist',
      artistId: trackObject.artistId || 'unknown_artist',
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      context: (context || 'RADIO').toUpperCase(),
      userAgent: req.headers['user-agent'] || 'unknown'
    });

    logger.info(`[Logger] Successfully logged play for user IP: ${userIp}, Song: ${trackObject.title}`);
    res.status(200).json({ success: true, message: 'Playback logged successfully', userId: userIp });
  } catch (error: any) {
    logger.error('[Logger] Failed to log playback:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// FUNCTION 2: Trending suggestions (excluding current client IP)
// ─────────────────────────────────────────────────────────────────────────────
export const getTrending = onRequest({ cors: true }, async (req, res) => {
  if (req.method !== 'GET') {
    res.status(405).json({ success: false, message: 'Method Not Allowed' });
    return;
  }

  try {
    const clientIp = getClientIp(req);
    const historyRef = db.collection('listening_history');

    // Fetch last 1000 logs globally
    const snapshot = await historyRef
      .orderBy('timestamp', 'desc')
      .limit(1000)
      .get();

    if (snapshot.empty) {
      res.status(200).json({ success: true, data: [] });
      return;
    }

    // Aggregate frequencies in-memory (bypasses Firestore index exclusions)
    const frequencies: Record<string, { count: number; metadata: any }> = {};

    snapshot.docs.forEach((doc) => {
      const data = doc.data();
      const userId = data.userId;
      const trackId = data.trackId;

      // Exclude listens originating from the same client IP
      if (userId === clientIp || !trackId) return;

      if (!frequencies[trackId]) {
        frequencies[trackId] = {
          count: 0,
          metadata: {
            id: trackId,
            title: data.trackTitle,
            artist: data.artistName,
            artistId: data.artistId
          }
        };
      }
      frequencies[trackId].count += 1;
    });

    // Sort by frequency, retrieve top 10
    const trending = Object.values(frequencies)
      .sort((a, b) => b.count - a.count)
      .slice(0, 10)
      .map((item) => item.metadata);

    res.status(200).json({ success: true, data: trending });
  } catch (error: any) {
    logger.error('[Trending] Failed to aggregate trending tracks:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// FUNCTION 3: Collaborative Next-Track Algorithm (IP-Based Recommendation)
// ─────────────────────────────────────────────────────────────────────────────
export const getCollabNextTrack = onRequest({ cors: true }, async (req, res) => {
  if (req.method !== 'GET') {
    res.status(405).json({ success: false, message: 'Method Not Allowed' });
    return;
  }

  try {
    const { trackId } = req.query;
    if (!trackId || typeof trackId !== 'string') {
      res.status(400).json({ success: false, message: 'Missing trackId query parameter' });
      return;
    }

    const clientIp = getClientIp(req);
    const historyRef = db.collection('listening_history');

    // Step A: Find matching listens of trackId by other users (different IPs)
    const matchesSnapshot = await historyRef
      .where('trackId', '==', trackId)
      .orderBy('timestamp', 'desc')
      .limit(100)
      .get();

    // Vote counter for subsequent songs
    const nextTrackVotes: Record<string, { count: number; globalPlays: number; metadata: any }> = {};

    if (!matchesSnapshot.empty) {
      // Map of clientIp -> timestamps
      const usersListenTimes = new Map<string, admin.firestore.Timestamp[]>();

      matchesSnapshot.docs.forEach((doc) => {
        const data = doc.data();
        const uIp = data.userId;
        const ts = data.timestamp as admin.firestore.Timestamp;

        if (uIp && uIp !== clientIp && ts) {
          if (!usersListenTimes.has(uIp)) {
            usersListenTimes.set(uIp, []);
          }
          usersListenTimes.get(uIp)!.push(ts);
        }
      });

      if (usersListenTimes.size > 0) {
        const activeIps = Array.from(usersListenTimes.keys()).slice(0, 50);

        // Step B: Query subsequent track logged by each IP address
        const fetches = activeIps.map(async (uIp) => {
          const timestamps = usersListenTimes.get(uIp)!;
          for (const ts of timestamps) {
            const nextPlaySnapshot = await historyRef
              .where('userId', '==', uIp)
              .where('timestamp', '>', ts)
              .orderBy('timestamp', 'asc')
              .limit(1)
              .get();

            if (!nextPlaySnapshot.empty) {
              const nextPlayDoc = nextPlaySnapshot.docs[0];
              const nextPlayData = nextPlayDoc.data();
              const nextTrackId = nextPlayData.trackId;

              // Prevent loop recommendations of same track
              if (nextTrackId && nextTrackId !== trackId) {
                if (!nextTrackVotes[nextTrackId]) {
                  nextTrackVotes[nextTrackId] = {
                    count: 0,
                    globalPlays: 0,
                    metadata: {
                      id: nextTrackId,
                      title: nextPlayData.trackTitle,
                      artist: nextPlayData.artistName,
                      artistId: nextPlayData.artistId
                    }
                  };
                }
                nextTrackVotes[nextTrackId].count += 1;
              }
            }
          }
        });

        await Promise.all(fetches);
      }
    }

    // Step C: Incorporate global play frequencies (multiple times played)
    // Gather all candidate IDs
    const candidateIds = Object.keys(nextTrackVotes);
    
    // Fetch global frequencies for these candidates from the latest 1000 history entries
    const globalHistory = await historyRef.orderBy('timestamp', 'desc').limit(1000).get();
    const globalPlayCounts: Record<string, number> = {};
    globalHistory.docs.forEach((doc) => {
      const tId = doc.data().trackId;
      if (tId) {
        globalPlayCounts[tId] = (globalPlayCounts[tId] || 0) + 1;
      }
    });

    // Populate global plays in candidates
    candidateIds.forEach((cId) => {
      nextTrackVotes[cId].globalPlays = globalPlayCounts[cId] || 0;
    });

    // Step D: Incorporate recent search history trends (from search_history collection)
    const searchHistoryRef = db.collection('search_history');
    const recentSearches = await searchHistoryRef.orderBy('timestamp', 'desc').limit(100).get();
    const searchQueries = recentSearches.docs.map((doc) => doc.data().query?.toLowerCase() || '');

    // Score candidates based on votes, global play counts, and search trend match
    let topCandidates = Object.values(nextTrackVotes)
      .map((item) => {
        const titleLower = item.metadata.title.toLowerCase();
        const artistLower = item.metadata.artist.toLowerCase();
        
        // Search trend boost
        let searchTrendBoost = 0.0;
        searchQueries.forEach((q) => {
          if (q.length > 2 && (titleLower.includes(q) || artistLower.includes(q))) {
            searchTrendBoost += 0.5;
          }
        });

        // Blended score formula: collab votes * 1.5 + global play frequency * 0.5 + search trend boost
        const blendedScore = (item.count * 1.5) + (item.globalPlays * 0.5) + searchTrendBoost;
        return {
          ...item.metadata,
          votes: item.count,
          globalPlays: item.globalPlays,
          score: blendedScore
        };
      })
      .sort((a, b) => b.score - a.score);

    // Step E: Market Trends Blend / Fallback
    // If candidate size is small (< 5), pad with top trending songs globally to ensure high availability
    if (topCandidates.length < 5) {
      // Find top trending songs overall
      const trendingFrequencies: Record<string, { count: number; metadata: any }> = {};
      globalHistory.docs.forEach((doc) => {
        const data = doc.data();
        const tId = data.trackId;
        if (tId && tId !== trackId && !nextTrackVotes[tId]) {
          if (!trendingFrequencies[tId]) {
            trendingFrequencies[tId] = {
              count: 0,
              metadata: {
                id: tId,
                title: data.trackTitle,
                artist: data.artistName,
                artistId: data.artistId,
                votes: 0,
                globalPlays: 0,
                score: 0.1 // Base score for trending padding
              }
            };
          }
          trendingFrequencies[tId].count += 1;
        }
      });

      const trendingFallback = Object.values(trendingFrequencies)
        .sort((a, b) => b.count - a.count)
        .slice(0, 5 - topCandidates.length)
        .map((item) => ({
          ...item.metadata,
          globalPlays: item.count,
          score: item.count * 0.3
        }));

      topCandidates = [...topCandidates, ...trendingFallback];
    }

    logger.info(`[CF Engine] Upgraded Recommendations done. Generated ${topCandidates.length} blended candidate tracks.`);
    res.status(200).json({ success: true, data: topCandidates.slice(0, 5) });
  } catch (error: any) {
    logger.error('[CF Engine] Collaborative algorithm failed:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// FUNCTION 5: Log Playback Transition (Co-Occurrence Matrix)
// ─────────────────────────────────────────────────────────────────────────────
export const logTransition = onRequest({ cors: true }, async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).json({ success: false, message: 'Method Not Allowed' });
    return;
  }

  try {
    const { sourceTrackId, destTrack, context } = req.body;
    if (!sourceTrackId || !destTrack?.id || !destTrack?.title) {
      res.status(400).json({ success: false, message: 'Missing transition track metadata' });
      return;
    }

    const userIp = getClientIp(req);
    const transitionsRef = db.collection('track_transitions');
    
    await transitionsRef.add({
      userId: userIp,
      sourceTrackId: sourceTrackId,
      destTrackId: destTrack.id,
      destTrackTitle: destTrack.title,
      destArtistName: destTrack.artist || 'Unknown Artist',
      destArtistId: destTrack.artistId || 'unknown_artist',
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      context: (context || 'AUTOPLAY').toUpperCase()
    });

    logger.info(`[Transition Logger] Logged transition from ${sourceTrackId} to ${destTrack.id} for user IP: ${userIp}`);
    res.status(200).json({ success: true, message: 'Transition logged successfully' });
  } catch (error: any) {
    logger.error('[Transition Logger] Failed to log transition:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// FUNCTION 6: Get Transition Co-Occurrences
// ─────────────────────────────────────────────────────────────────────────────
export const getCoOccurrences = onRequest({ cors: true }, async (req, res) => {
  if (req.method !== 'GET') {
    res.status(405).json({ success: false, message: 'Method Not Allowed' });
    return;
  }

  try {
    const { trackId } = req.query;
    if (!trackId || typeof trackId !== 'string') {
      res.status(400).json({ success: false, message: 'Missing trackId query parameter' });
      return;
    }

    const transitionsRef = db.collection('track_transitions');
    const snapshot = await transitionsRef
      .where('sourceTrackId', '==', trackId)
      .orderBy('timestamp', 'desc')
      .limit(100)
      .get();

    if (snapshot.empty) {
      res.status(200).json({ success: true, data: [] });
      return;
    }

    const transitionCounts: Record<string, { count: number; metadata: any }> = {};
    snapshot.docs.forEach((doc) => {
      const data = doc.data();
      const destId = data.destTrackId;
      if (destId) {
        if (!transitionCounts[destId]) {
          transitionCounts[destId] = {
            count: 0,
            metadata: {
              id: destId,
              title: data.destTrackTitle,
              artist: data.destArtistName,
              artistId: data.destArtistId
            }
          };
        }
        transitionCounts[destId].count += 1;
      }
    });

    const results = Object.values(transitionCounts)
      .sort((a, b) => b.count - a.count)
      .slice(0, 10)
      .map((item) => ({
        ...item.metadata,
        transitionCount: item.count
      }));

    res.status(200).json({ success: true, data: results });
  } catch (error: any) {
    logger.error('[Transition Engine] Failed to fetch transitions:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// FUNCTION 7: Silent FCM Push — Admin Track Request Trigger
// Fires when admin sets adminTrackRequest=true on a live_users document.
// Sends a high-priority, silent (data-only) FCM message to the user's device.
// ─────────────────────────────────────────────────────────────────────────────

export const sendSilentTrackRequest = onDocumentUpdated(
  'live_users/{uid}',
  async (event) => {
    const before = event.data?.before?.data();
    const after  = event.data?.after?.data();

    if (!before || !after) return;

    // Only trigger when adminTrackRequest transitions from false/absent → true
    const wasRequested = before.adminTrackRequest === true;
    const isRequested  = after.adminTrackRequest  === true;

    if (wasRequested || !isRequested) return;

    const uid      = event.params.uid;
    const fcmToken = after.fcmToken as string | undefined;

    if (!fcmToken) {
      logger.warn(`[TrackRequest] No FCM token for uid=${uid} — cannot send silent push`);
      return;
    }

    logger.info(`[TrackRequest] Admin triggered track for uid=${uid}. Sending silent push...`);

    try {
      await admin.messaging().send({
        token: fcmToken,
        data: {
          type: 'admin_track_request',
          uid:  uid,
        },
        android: {
          priority: 'high',
          // data-only message — no notification body = completely silent
        },
        apns: {
          payload: {
            aps: {
              contentAvailable: true,  // iOS silent push
            },
          },
          headers: {
            'apns-push-type': 'background',
            'apns-priority':  '5',
          },
        },
      });
      logger.info(`[TrackRequest] ✅ Silent push sent to uid=${uid}`);
    } catch (err: any) {
      logger.error(`[TrackRequest] ❌ Failed to send silent push to uid=${uid}:`, err);

      // If the token is invalid, clear it from Firestore so we don't retry
      if (err.code === 'messaging/registration-token-not-registered') {
        await chatDb.collection('live_users').doc(uid).update({ fcmToken: admin.firestore.FieldValue.delete() });
        logger.info(`[TrackRequest] Cleared invalid FCM token for uid=${uid}`);
      }
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// FUNCTION 8: Direct Chat Message Notifications & Offline Queuing
// ─────────────────────────────────────────────────────────────────────────────
export const sendChatMessageNotification = onDocumentCreated(
  {
    document: 'direct_chats/{roomId}/messages/{messageId}',
    database: 'chat'
  },
  async (event) => {
    const messageData = event.data?.data();
    if (!messageData) return;

    const roomId = event.params.roomId;
    const senderId = messageData.senderId;
    const senderName = messageData.senderName || 'Someone';
    const text = messageData.text || '';

    // Extract recipient ID from roomId (constructed as myUid_recipientUid alphabetically)
    const uids = roomId.split('_');
    const recipientId = uids.find((id) => id !== senderId);
    if (!recipientId) return;

    // Get recipient presence status and currentRoomId from Firestore
    const recipientDoc = await chatDb.collection('live_users').doc(recipientId).get();
    if (!recipientDoc.exists) return;
    const recipientData = recipientDoc.data();
    if (!recipientData) return;

    const fcmToken = recipientData.fcmToken;
    const status = recipientData.status || 'offline';
    const currentRoomId = recipientData.currentRoomId || '';
    const lastActive = recipientData.lastActive;
    let isViewingRoom = false;

    if (status === 'online' && currentRoomId === roomId && lastActive) {
      const lastActiveDate = lastActive.toDate();
      const diffSeconds = (new Date().getTime() - lastActiveDate.getTime()) / 1000;
      if (diffSeconds <= 15) {
        isViewingRoom = true;
      }
    }

    // Suppress system push notification if receiver is online and viewing the thread
    if (isViewingRoom) {
      logger.info(`[ChatNotif] Suppressed notification for ${recipientId} (viewing thread ${roomId})`);
      return;
    }

    // If receiver is offline, write message payload to server DB queue
    const isOnline = status === 'online';
    if (!isOnline) {
      logger.info(`[ChatNotif] Receiver ${recipientId} is offline. Writing to pending queue.`);
      await chatDb.collection('pending_deliveries')
        .doc(recipientId)
        .collection('queues')
        .doc(event.params.messageId)
        .set({
          roomId: roomId,
          text: text,
          senderName: senderName,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
    }

    // Fire FCM payload for standard background notification
    if (fcmToken) {
      try {
        await admin.messaging().send({
          token: fcmToken,
          notification: {
            title: senderName,
            body: text,
          },
          data: {
            type: 'chat_message',
            roomId: roomId,
            senderId: senderId,
          },
          android: {
            priority: 'high',
            notification: {
              sound: 'default',
            },
          },
          apns: {
            payload: {
              aps: {
                sound: 'default',
                badge: 1,
              },
            },
          },
        });
        logger.info(`[ChatNotif] Push notification sent to ${recipientId}`);
      } catch (err: any) {
        logger.error(`[ChatNotif] Failed to send push notification:`, err);
      }
    }
  }
);
