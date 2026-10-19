import localUnitTest from './LocalUnit.test';
import reminderModelTest from './ReminderModel.test';
import reminderRepositoryTest from './ReminderRepository.test';
import reminderTriggerPortTest from './ReminderTriggerPort.test';
import reminderServiceTest from './ReminderService.test';
import aiContractsTest from './AIContracts.test';
import aiResponseParserTest from './AIResponseParser.test';

export default function testsuite() {
  localUnitTest();
  reminderModelTest();
  reminderRepositoryTest();
  reminderTriggerPortTest();
  reminderServiceTest();
  aiContractsTest();
  aiResponseParserTest();
}
