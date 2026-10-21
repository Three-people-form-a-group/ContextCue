import localUnitTest from './LocalUnit.test';
import reminderModelTest from './ReminderModel.test';
import reminderRepositoryTest from './ReminderRepository.test';
import reminderTriggerPortTest from './ReminderTriggerPort.test';
import reminderEventContractTest from './ReminderEventContract.test';
import triggerCoordinatorTest from './TriggerCoordinator.test';
import reminderServiceTest from './ReminderService.test';
import aiContractsTest from './AIContracts.test';
import aiResponseParserTest from './AIResponseParser.test';
import aiParseValidatorTest from './AIParseValidator.test';
import reminderMapperTest from './ReminderMapper.test';
import aiServiceTest from './AIService.test';

export default function testsuite() {
  localUnitTest();
  reminderModelTest();
  reminderRepositoryTest();
  reminderTriggerPortTest();
  reminderEventContractTest();
  triggerCoordinatorTest();
  reminderServiceTest();
  aiContractsTest();
  aiResponseParserTest();
  aiParseValidatorTest();
  reminderMapperTest();
  aiServiceTest();
}
