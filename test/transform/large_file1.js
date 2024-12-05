import React, { useState, useEffect, useRef } from 'react';
import { useParams } from 'react-router-dom';
import styled from 'styled-components';
import { MessageWrapper, MessageBubble, MessageTime } from './shared/MessageBubbleStyles';
import useChatStore from '../store/chatStore';
import { useMessages, useMessageActions } from '../store/messagesStore';
import ReactMarkdown from 'react-markdown';
import LectoredIcon from './LectoredIcon';
import { updateDoc, doc,  addDoc, collection, serverTimestamp } from "firebase/firestore";
import { firestoreDB } from "../services/firebase";

const MessageListContainer = styled.div`
  flex: 1;
  overflow-y: auto;
  padding: 20px;
  display: flex;
  flex-direction: column;

  /* Custom scrollbar styles */
  scrollbar-width: thin;
  scrollbar-color: #6b6b6b #3a3a3a;

  &::-webkit-scrollbar {
    width: 8px;
  }

  &::-webkit-scrollbar-track {
    background: #3a3a3a;
    border-radius: 4px;
  }

  &::-webkit-scrollbar-thumb {
    background-color: #6b6b6b;
    border-radius: 4px;
    border: 2px solid #3a3a3a;
  }

  &::-webkit-scrollbar-thumb:hover {
    background-color: #888;
  }
`;


const TranslationSeparator = styled.hr`
  border: 0;
  height: 1px;
  background-color: rgba(255, 255, 255, 0.3);
  margin: 8px 0;
`;

const OriginalText = styled(ReactMarkdown)`
  p {
    margin: 0;
    padding: 0;
  }
  
  * :first-child {
    margin-top: 0;
  }
  
  * :last-child {
    margin-bottom: 0;
  }
`;

const TranslatedText = styled(OriginalText)`
  font-style: italic;
  font-size: 0.9em;
  opacity: 0.9;
`;

const SelectionIndicator = styled.div`
  position: absolute;
  right: 5px;
  bottom: 5px;
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background-color: #f39c12;
  opacity: ${({ isSelected }) => isSelected ? 1 : 0};
  transition: opacity 0.2s;
`;

const ContextMenu = styled.div`
  position: fixed;
  background-color: #2c2c2c;
  border-radius: 8px;
  padding: 8px 0;
  box-shadow: 0 2px 10px rgba(0, 0, 0, 0.3);
  z-index: 1000;
`;

const MenuItem = styled.div`
  padding: 8px 16px;
  cursor: pointer;
  color: white;
  
  &:hover {
    background-color: #3a3a3a;
  }
`;

const TestCaseInput = styled.textarea`
  width: 100%;
  background-color: #3a3a3a;
  color: white;
  border: none;
  border-radius: 4px;
  padding: 8px;
  margin-top: 4px;
  resize: vertical;
  min-height: 60px;
  font-size: 14px;         
  line-height: 1.4;        

  &:focus {
    outline: none;
    border: 1px solid #3498db;
  }

  &::placeholder {
    color: #aaaaaa;        
  }
`;

const TestCaseModal = styled.div`
  position: fixed;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%);
  background-color: #2c2c2c;
  padding: 20px;
  border-radius: 8px;
  box-shadow: 0 2px 10px rgba(0, 0, 0, 0.3);
  z-index: 1000;
  width: 90%;
  max-width: 500px;
  color: #ffffff;
`;

const ModalContent = styled.div`
  display: flex;
  flex-direction: column;
  gap: 15px;
`;

const RelevancySelect = styled.select`
  background-color: #3a3a3a;
  color: white;
  border: 1px solid #4a4a4a;
  padding: 8px;
  border-radius: 4px;
  width: 100%;
  margin-top: 4px;

  &:focus {
    outline: none;
    border-color: #3498db;
  }

  option {
    background-color: #2c2c2c;
  }
`;

const ModalButtons = styled.div`
  display: flex;
  justify-content: flex-end;
  gap: 10px;
  margin-top: 16px;
`;

const Button = styled.button`
  padding: 8px 16px;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  background-color: ${props => props.primary ? '#3498db' : '#6b6b6b'};
  color: white;

  &:hover {
    background-color: ${props => props.primary ? '#2980b9' : '#5a5a5a'};
  }
`;

// Temporary translation function (placeholder)
const getTemporaryTranslation = (text) => {
  return `[HU] ${text.split(' ').reverse().join(' ')}`;
};

const MessageItem = ({ message, isSenderMessage, isSelected, onSelect, onLectoredToggle, showTranslation }) => {
  const { uid } = useParams();
  const [contextMenu, setContextMenu] = useState(null);
  const [showTestCaseModal, setShowTestCaseModal] = useState(false);
  const [testCaseCondition, setTestCaseCondition] = useState('');
  const [testCaseRelevancy, setTestCaseRelevancy] = useState('normal');

  const handleContextMenu = (e) => {
    e.preventDefault();
    setContextMenu({ x: e.clientX, y: e.clientY });
  };

  const handleClickOutside = () => {
    setContextMenu(null);
  };

  useEffect(() => {
    if (contextMenu) {
      document.addEventListener('click', handleClickOutside);
      return () => document.removeEventListener('click', handleClickOutside);
    }
  }, [contextMenu]);

  const handleTestCaseSubmit = async () => {
    try {
      await addDoc(collection(firestoreDB, 'testcases'), {
        messageId: message.id,
        chatId: uid,
        condition: testCaseCondition,
        relevancy: testCaseRelevancy,
        timestamp: serverTimestamp(),
        messageText: message.text,
      });
      setShowTestCaseModal(false);
      setTestCaseCondition('');
      setTestCaseRelevancy('normal');
    } catch (error) {
      console.error('Error saving test case:', error);
    }
  };

  return (
    <MessageWrapper isAssistant={message.userId === 'assistant'}>
      {message.userId === 'assistant' && (
        <LectoredIcon
          active={message.isLectored}
          onClick={() => onLectoredToggle(message.id)}
          activeIconSrc={`${process.env.PUBLIC_URL}/Lectored.png`} 
          inactiveIconSrc={`${process.env.PUBLIC_URL}/Unlectored.png`}
          size="20px"
        />
      )}
      <MessageBubble 
        isAssistant={message.userId === 'assistant'}
        isSelected={isSelected}
        onClick={(e) => {
          e.preventDefault();
          handleContextMenu(e);
        }}
        onContextMenu={handleContextMenu}
      >
        <OriginalText>{message.text}</OriginalText>
        {showTranslation && message.translation && (
          <>
            <TranslationSeparator />
            <TranslatedText>{message.translation}</TranslatedText>
          </>
        )}
        <SelectionIndicator isSelected={isSelected} />
      </MessageBubble>
      {message.userId !== 'assistant' && (
        <LectoredIcon
          active={message.isLectored}
          onClick={() => onLectoredToggle(message.id)}
          activeIconSrc={`${process.env.PUBLIC_URL}/Lectored.png`} 
          inactiveIconSrc={`${process.env.PUBLIC_URL}/Unlectored.png`}
          size="20px"
        />
      )}
      
      {contextMenu && (
        <ContextMenu style={{ top: contextMenu.y, left: contextMenu.x }}>
          <MenuItem onClick={() => {
            setShowTestCaseModal(true);
            setContextMenu(null);
          }}>
            Write testcase condition
          </MenuItem>
          <MenuItem onClick={() => {
            onSelect(message.id);
            setContextMenu(null);
          }}>
            Select message
          </MenuItem>
        </ContextMenu>
      )}

      {showTestCaseModal && (
        <TestCaseModal>
          <h3>Write Test Case Condition</h3>
          <ModalContent>
            <div>
              <p>Specify the condition that should be true for the answer:</p>
              <TestCaseInput
                value={testCaseCondition}
                onChange={(e) => setTestCaseCondition(e.target.value)}
                placeholder="e.g., 'The answer should include specific dietary recommendations' or 'The response must mention exercise guidelines'"
              />
            </div>
            <div>
              <p>Select relevancy level:</p>
              <RelevancySelect
                value={testCaseRelevancy}
                onChange={(e) => setTestCaseRelevancy(e.target.value)}
              >
                <option value="note">Note</option>
                <option value="normal">Normal</option>
                <option value="important">Important</option>
              </RelevancySelect>
            </div>
          </ModalContent>
          <ModalButtons>
            <Button onClick={() => setShowTestCaseModal(false)}>Cancel</Button>
            <Button primary onClick={handleTestCaseSubmit}>Save Test Case</Button>
          </ModalButtons>
        </TestCaseModal>
      )}
    </MessageWrapper>
  );
};

const MessageList = () => {
  const { uid } = useParams();
  const messages = useMessages(uid);
  const { updateMessage } = useMessageActions();
  const {
    setSelectedMessages,
    selectedMessageIds,
    setSelectedMessageIds,
    isAutoTranslate,
    translateAllMessages,
    language
  } = useChatStore();
  const messageListRef = useRef(null);

  useEffect(() => {
    // Clear selected messages when uid changes
    setSelectedMessages([]);
    setSelectedMessageIds(new Set());
  }, [uid, setSelectedMessages, setSelectedMessageIds]);

  const toggleMessageSelection = (messageId) => {
    setSelectedMessageIds(prevSelected => {
      const newSelected = new Set(prevSelected);
      if (newSelected.has(messageId)) {
        newSelected.delete(messageId);
      } else {
        newSelected.add(messageId);
      }
      return newSelected;
    });
  };

  const toggleMessageLectored = async (messageId) => {
    const msg = messages.find(message => message.id === messageId);

    try {
      await updateDoc(doc(firestoreDB, `chats/${uid}/messages/${messageId}`), { 
        isLectored: !msg.isLectored
      });
      updateMessage(uid, messageId, { isLectored: !msg.isLectored });
    } catch (error) {
      console.error("Error updating lectored status:", error);
    }
  };

  useEffect(() => {
    setSelectedMessages(messages.filter(message => selectedMessageIds.has(message.id)))
  }, [selectedMessageIds, messages, setSelectedMessages]);

  useEffect(() => {
    if (messageListRef.current) {
      messageListRef.current.scrollTop = messageListRef.current.scrollHeight;
    }
  }, [messages]);

  useEffect(() => {    
    if (isAutoTranslate && language !== 'hu') {
      translateAllMessages('Hungarian');
    }
  }, [isAutoTranslate, translateAllMessages, language]);

  return (
    <MessageListContainer ref={messageListRef}>
      {messages.map(message => (
        <MessageItem
          key={message.id}
          message={message}
          isSelected={selectedMessageIds.has(message.id)}
          onSelect={toggleMessageSelection}
          onLectoredToggle={toggleMessageLectored}
          showTranslation={isAutoTranslate && language !== 'hu'}
        />
      ))}
    </MessageListContainer>
  );
};

export default MessageList;
