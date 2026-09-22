import { createElement } from "lwc";
import LineChat from "c/lineChat";
import getConversations from "@salesforce/apex/LineChatController.getConversations";
import getMessages from "@salesforce/apex/LineChatController.getMessages";
import getMessagesSince from "@salesforce/apex/LineChatController.getMessagesSince";
import markRead from "@salesforce/apex/LineChatController.markRead";
import sendText from "@salesforce/apex/LineChatController.sendText";
import getPollIntervalSeconds from "@salesforce/apex/LineChatController.getPollIntervalSeconds";

jest.mock(
  "@salesforce/apex/LineChatController.getConversations",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LineChatController.getMessages",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/LineChatController.getMessagesSince",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/LineChatController.markRead",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/LineChatController.sendText",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/LineChatController.getPollIntervalSeconds",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const CONVERSATION = {
  id: "a00000000000001",
  name: "Somchai",
  status: "Following",
  unreadCount: 2,
  oaName: "OA A",
  isPrimaryOa: true
};

function inboundMessage(id, text, sentAt = "2026-09-22T03:00:00.000Z") {
  return {
    id,
    text,
    sentAt,
    isOutbound: false,
    direction: "Inbound",
    messageType: "text",
    status: "Received"
  };
}

function setVisibility(state) {
  Object.defineProperty(document, "visibilityState", {
    value: state,
    configurable: true
  });
  document.dispatchEvent(new CustomEvent("visibilitychange"));
}

async function flush() {
  // Let the component's chained promises settle (six microtask ticks).
  await Promise.resolve().then().then().then().then().then().then();
}

function createComponent() {
  const element = createElement("c-line-chat", { is: LineChat });
  element.recordId = "003000000000001";
  document.body.appendChild(element);
  return element;
}

describe("c-line-chat", () => {
  beforeEach(() => {
    jest.useFakeTimers();
    setVisibility("visible");
    getPollIntervalSeconds.mockResolvedValue(5);
    getConversations.mockResolvedValue([CONVERSATION]);
    getMessages.mockResolvedValue({
      messages: [inboundMessage("m1", "สวัสดีครับ")],
      hasMore: false
    });
    getMessagesSince.mockResolvedValue([]);
    markRead.mockResolvedValue(0);
    sendText.mockResolvedValue({
      id: "m2",
      text: "Hello",
      sentAt: "2026-09-22T03:05:00.000Z",
      isOutbound: true,
      direction: "Outbound",
      messageType: "text",
      status: "Sent"
    });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.useRealTimers();
  });

  it("renders the conversation history and marks it read", async () => {
    const element = createComponent();
    await flush();

    expect(getConversations).toHaveBeenCalledWith({
      contactId: "003000000000001"
    });
    const bubbles = element.shadowRoot.querySelectorAll(".line-bubble");
    expect(bubbles.length).toBe(1);
    expect(bubbles[0].textContent).toContain("สวัสดีครับ");
    expect(markRead).toHaveBeenCalledWith({ conversationId: CONVERSATION.id });
  });

  it("shows the empty state with an invite button when there is no conversation", async () => {
    getConversations.mockResolvedValue([]);
    const element = createComponent();
    await flush();

    expect(element.shadowRoot.querySelectorAll(".line-bubble").length).toBe(0);
    const button = element.shadowRoot.querySelector("lightning-button");
    expect(button).not.toBeNull();
    expect(getMessages).not.toHaveBeenCalled();
  });

  it("renders a placeholder instead of content for non-text messages", async () => {
    getMessages.mockResolvedValue({
      messages: [
        { ...inboundMessage("m1", null), messageType: "image" },
        {
          ...inboundMessage("m2", null),
          messageType: "file",
          fileName: "quote.pdf"
        }
      ],
      hasMore: false
    });
    const element = createComponent();
    await flush();

    const text = element.shadowRoot.querySelector(".line-messages").textContent;
    expect(text).toContain("quote.pdf");
    expect(element.shadowRoot.querySelectorAll(".line-bubble").length).toBe(2);
  });

  it("sends a message and appends it", async () => {
    const element = createComponent();
    await flush();

    // The stub element carries the value; the change event's target is the element itself.
    const textarea = element.shadowRoot.querySelector("lightning-textarea");
    textarea.value = "Hello";
    textarea.dispatchEvent(new CustomEvent("change"));
    await flush();

    const sendButton = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].pop();
    sendButton.dispatchEvent(new CustomEvent("click"));
    await flush();

    expect(sendText).toHaveBeenCalledWith({
      conversationId: CONVERSATION.id,
      text: "Hello"
    });
    expect(element.shadowRoot.querySelectorAll(".line-bubble").length).toBe(2);
  });

  it("shows an error toast when sending fails", async () => {
    sendText.mockRejectedValue({
      body: { message: "This LINE OA has used its monthly message allowance." }
    });
    const element = createComponent();
    await flush();
    const toastHandler = jest.fn();
    element.addEventListener("lightning__showtoast", toastHandler);

    const textarea = element.shadowRoot.querySelector("lightning-textarea");
    textarea.value = "Hello";
    textarea.dispatchEvent(new CustomEvent("change"));
    await flush();
    [...element.shadowRoot.querySelectorAll("lightning-button")]
      .pop()
      .dispatchEvent(new CustomEvent("click"));
    await flush();

    expect(toastHandler).toHaveBeenCalled();
    expect(toastHandler.mock.calls[0][0].detail.message).toContain(
      "monthly message allowance"
    );
    expect(element.shadowRoot.querySelectorAll(".line-bubble").length).toBe(1);
  });

  it("polls only while the tab is visible", async () => {
    createComponent();
    await flush();
    expect(getMessagesSince).not.toHaveBeenCalled();

    jest.advanceTimersByTime(5000);
    await flush();
    expect(getMessagesSince).toHaveBeenCalledTimes(1);

    setVisibility("hidden");
    await flush();
    jest.advanceTimersByTime(20000);
    await flush();
    expect(getMessagesSince).toHaveBeenCalledTimes(1);

    setVisibility("visible");
    await flush();
    expect(getMessagesSince).toHaveBeenCalledTimes(2);
  });

  it("appends polled messages and skips ones it already has", async () => {
    const element = createComponent();
    await flush();
    getMessagesSince.mockResolvedValue([
      inboundMessage("m1", "สวัสดีครับ"),
      inboundMessage("m9", "new one", "2026-09-22T03:10:00.000Z")
    ]);

    jest.advanceTimersByTime(5000);
    await flush();

    expect(element.shadowRoot.querySelectorAll(".line-bubble").length).toBe(2);
    expect(
      element.shadowRoot.querySelector(".line-messages").textContent
    ).toContain("new one");
    expect(markRead).toHaveBeenCalledTimes(2);
  });

  it("stops polling when the component is removed", async () => {
    const element = createComponent();
    await flush();
    document.body.removeChild(element);

    jest.advanceTimersByTime(30000);
    await flush();

    expect(getMessagesSince).not.toHaveBeenCalled();
  });

  it("loads older messages on demand", async () => {
    getMessages.mockResolvedValueOnce({
      messages: [inboundMessage("m5", "newest page")],
      hasMore: true
    });
    const element = createComponent();
    await flush();

    getMessages.mockResolvedValueOnce({
      messages: [
        inboundMessage("m4", "older page", "2026-09-22T02:00:00.000Z")
      ],
      hasMore: false
    });
    element.shadowRoot
      .querySelector("lightning-button")
      .dispatchEvent(new CustomEvent("click"));
    await flush();

    const bubbles = element.shadowRoot.querySelectorAll(".line-bubble");
    expect(bubbles.length).toBe(2);
    expect(bubbles[0].textContent).toContain("older page");
    expect(getMessages).toHaveBeenLastCalledWith({
      conversationId: CONVERSATION.id,
      beforeSentAt: "2026-09-22T03:00:00.000Z",
      beforeId: "m5",
      pageSize: null
    });
  });

  it("shows an error when the conversation cannot be read", async () => {
    getConversations.mockRejectedValue({ body: { message: "No access" } });
    const element = createComponent();
    await flush();

    expect(element.shadowRoot.textContent).toContain("No access");
  });
});
