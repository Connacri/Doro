class SignalingProtocol {
  static Map<String, dynamic> register(String id) => {
    "type": "register",
    "id": id,
  };

  static Map<String, dynamic> offer(String to, dynamic sdp) => {
    "type": "offer",
    "to": to,
    "sdp": sdp,
  };

  static Map<String, dynamic> answer(String to, dynamic sdp) => {
    "type": "answer",
    "to": to,
    "sdp": sdp,
  };

  static Map<String, dynamic> ice(String to, dynamic candidate) => {
    "type": "ice",
    "to": to,
    "candidate": candidate,
  };
}